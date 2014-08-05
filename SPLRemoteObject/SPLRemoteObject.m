//
//  SPLRemoteObject.m
//  SPLRemoteObject
//
//  The MIT License (MIT)
//  Copyright (c) 2013 Oliver Letterer, Sparrow-Labs
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "SPLRemoteObject.h"
#import "NSString+SPLRemoteObject.h"
#import "_SPLRemoteObjectProxyBrowser.h"
#import "NSInvocation+SPLRemoteObject.h"
#import "_SPLRemoteObjectHostConnection.h"
#import "SLBlockDescription.h"
#import "_SPLNil.h"
#import "_SPLIncompatibleResponse.h"
#import <objc/runtime.h>
#import <dns_sd.h>
#import <net/if.h>
#import <AssertMacros.h>

static void invokeCompletionHandler(id genericCompletionBlock, id object, NSError *error) {
    if (!genericCompletionBlock) {
        return;
    }

    SLBlockDescription *blockDescription = [[SLBlockDescription alloc] initWithBlock:genericCompletionBlock];
    NSMethodSignature *blockSignature = blockDescription.blockSignature;

    if (blockSignature.numberOfArguments == 3) {
        void(^completionBlock)(id object, NSError *error) = genericCompletionBlock;

        if (object) {
            NSString *className = [NSString stringWithFormat:@"%s", [blockSignature getArgumentTypeAtIndex:1]];
            className = [className substringWithRange:NSMakeRange(2, className.length - 3)];

            if (![object isKindOfClass:NSClassFromString(className)]) {
                object = nil;
                error = [NSError errorWithDomain:SPLRemoteObjectErrorDomain code:SPLRemoteObjectConnectionIncompatibleProtocol userInfo:NULL];
            }
        }

        if ([NSThread currentThread].isMainThread) {
            completionBlock(object, error);
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(object, error);
            });
        }
    } else if (blockSignature.numberOfArguments == 2) {
        void(^completionBlock)(NSError *error) = genericCompletionBlock;
        if ([NSThread currentThread].isMainThread) {
            completionBlock(error);
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(error);
            });
        }
    } else {
        NSCAssert(NO, @"block %@ signature not supported: %@", genericCompletionBlock, blockSignature);
    }
};



char * const SPLRemoteObjectInvocationKey;

static BOOL signatureMatches(const char *signature1, const char *signature2)
{
    return signature1[0] == signature2[0];
}

@interface _SPLRemoteObjectQueuedConnection : NSObject

@property (nonatomic, copy) id completionBlock;
@property (nonatomic, strong) NSData *dataPackage;
@property (nonatomic, assign) BOOL shouldRetryIfConnectionFails;

@end

@interface _SPLRemoteObjectConnection (SPLRemoteObject)
@property (nonatomic, assign) BOOL shouldRetryIfConnectionFails;
@end

@implementation _SPLRemoteObjectConnection (SPLRemoteObject)

- (BOOL)shouldRetryIfConnectionFails
{
    return [objc_getAssociatedObject(self, @selector(shouldRetryIfConnectionFails)) boolValue];
}

- (void)setShouldRetryIfConnectionFails:(BOOL)shouldRetryIfConnectionFails
{
    objc_setAssociatedObject(self, @selector(shouldRetryIfConnectionFails), @(shouldRetryIfConnectionFails), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end



static void * SPLRemoteObjectObserver = &SPLRemoteObjectObserver;

@interface SPLRemoteObject () <_SPLRemoteObjectConnectionDelegate, NSNetServiceDelegate>

@property (nonatomic, strong) _SPLRemoteObjectProxyBrowser *hostBrowser;

@property (nonatomic, strong) NSMutableArray *activeConnection;
@property (nonatomic, strong) NSMutableArray *queuedConnections;

@property (nonatomic, strong) NSNetService *netService;
@property (nonatomic, copy) NSDictionary *userInfo;

@property (nonatomic, assign) SPLRemoteObjectReachabilityStatus reachabilityStatus;

@end



@implementation SPLRemoteObject

+ (NSDictionary *)userInfoFromTXTRecordData:(NSData *)txtData
{
    NSDictionary *dictionary = [NSNetService dictionaryFromTXTRecordData:txtData];
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];

    [dictionary enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSData *data, BOOL *stop) {
        id object = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        if (object) {
            userInfo[key] = object;
        }
    }];

    return [userInfo copy];
}

#pragma mark - setters and getters

- (void)setNetService:(NSNetService *)netService
{
    if (netService != _netService) {
        _netService = netService;

        self.reachabilityStatus = _netService != nil ? SPLRemoteObjectReachabilityStatusAvailable : SPLRemoteObjectReachabilityStatusUnavailable;

        if (_netService) {
            for (_SPLRemoteObjectQueuedConnection *queuedConnection in _queuedConnections) {
                NSInvocation *invocation = objc_getAssociatedObject(queuedConnection, &SPLRemoteObjectInvocationKey);
                NSParameterAssert(invocation);

                // -1 operation from queue
                [[NSNotificationCenter defaultCenter] postNotificationName:SPLRemoteObjectNetworkOperationDidEndNotification object:nil];

                _SPLRemoteObjectHostConnection *connection = [[_SPLRemoteObjectHostConnection alloc] initWithHostAddress:_netService.hostName port:_netService.port];
                connection.completionBlock = queuedConnection.completionBlock;
                connection.delegate = self;
                connection.shouldRetryIfConnectionFails = queuedConnection.shouldRetryIfConnectionFails;
                objc_setAssociatedObject(connection, &SPLRemoteObjectInvocationKey, invocation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                [_activeConnection addObject:connection];

                [connection connect];
                [connection sendDataPackage:queuedConnection.dataPackage];
            }

            [_queuedConnections removeAllObjects];
        }
    }
}

- (BOOL)conformsToProtocol:(Protocol *)aProtocol
{
    return [super conformsToProtocol:aProtocol] || aProtocol == self.protocol;
}

#pragma mark - Initialization

- (instancetype)initWithNetService:(NSNetService *)netService type:(NSString *)type protocol:(Protocol *)protocol
{
    if (self = [super init]) {
        _netService = netService;

        _name = netService.name;
        _type = type;
        _protocol = protocol;
        _timeoutInterval = 10.0;

        _activeConnection = [NSMutableArray array];
        _queuedConnections = [NSMutableArray array];

        _netService.delegate = self;
        [_netService scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        [_netService resolveWithTimeout:self.timeoutInterval];
    }
    return self;
}

- (instancetype)initWithName:(NSString *)name type:(NSString *)type protocol:(Protocol *)protocol
{
    if (self = [super init]) {
        _name = name;
        _type = type;
        _protocol = protocol;
        _timeoutInterval = 10.0;

        _activeConnection = [NSMutableArray array];
        _queuedConnections = [NSMutableArray array];

        _hostBrowser = [[_SPLRemoteObjectProxyBrowser alloc] initWithName:self.name netServiceType:[self.type netServiceTypeWithProtocol:self.protocol]];
        [_hostBrowser addObserver:self forKeyPath:NSStringFromSelector(@selector(userInfo)) options:NSKeyValueObservingOptionNew context:SPLRemoteObjectObserver];
        [_hostBrowser addObserver:self forKeyPath:NSStringFromSelector(@selector(resolvedNetService)) options:NSKeyValueObservingOptionNew context:SPLRemoteObjectObserver];
        [_hostBrowser startDiscoveringRemoteObjectHosts];
    }
    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == SPLRemoteObjectObserver) {
        if ([keyPath isEqual:NSStringFromSelector(@selector(userInfo))]) {
            self.userInfo = self.hostBrowser.userInfo;
        } else if ([keyPath isEqual:NSStringFromSelector(@selector(resolvedNetService))]) {
            self.netService = self.hostBrowser.resolvedNetService;
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - NSNetServiceDelegate

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
    NSLog(@"%@", errorDict);
    NSParameterAssert(errorDict);
}

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
    self.reachabilityStatus = SPLRemoteObjectReachabilityStatusAvailable;
    [self.netService startMonitoring];
}

- (void)netService:(NSNetService *)sender didUpdateTXTRecordData:(NSData *)data
{
    self.userInfo = [SPLRemoteObject userInfoFromTXTRecordData:data];
}

#pragma mark - NSObject

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    struct objc_method_description methodDescription = protocol_getMethodDescription(_protocol, aSelector, YES, YES);

    if (!methodDescription.types) {
        NSLog(@"seems like protocol %s does not contain selector %@", protocol_getName(_protocol), NSStringFromSelector(aSelector));
        [self doesNotRecognizeSelector:aSelector];
    }

    return [NSMethodSignature signatureWithObjCTypes:methodDescription.types];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    [self _forwardInvocation:anInvocation shouldRetryIfConnectionFails:YES];
}

#pragma mark - _SPLRemoteObjectConnectionDelegate

- (void)remoteObjectConnectionConnectionAttemptFailed:(_SPLRemoteObjectConnection *)connection
{
    _SPLRemoteObjectHostConnection *hostConnection = (_SPLRemoteObjectHostConnection *)connection;

    NSInvocation *invocation = objc_getAssociatedObject(hostConnection, &SPLRemoteObjectInvocationKey);
    NSParameterAssert(invocation);

    if (connection.shouldRetryIfConnectionFails) {
        BOOL isDiscovering = _hostBrowser.isDiscoveringRemoteObjectHosts;

        if (isDiscovering) {
            [_hostBrowser stopDiscoveringRemoteObjectHosts];
        }

        [self _invalidateDNSCache];

        if (isDiscovering) {
            [_hostBrowser startDiscoveringRemoteObjectHosts];
        }

        [self _forwardInvocation:invocation shouldRetryIfConnectionFails:NO];

        return;
    }

    if (hostConnection.completionBlock) {
        NSDictionary *userInfo = @{
                                   NSLocalizedDescriptionKey: NSLocalizedString(@"Connection to remote host failed", @"")
                                   };
        NSError *error = [NSError errorWithDomain:SPLRemoteObjectErrorDomain
                                             code:SPLRemoteObjectConnectionFailed
                                         userInfo:userInfo];
        invokeCompletionHandler(hostConnection.completionBlock, nil, error);
        hostConnection.completionBlock = nil;
    }

    // this must be asynced to the main queue because the current runloop is retaining the inputstream of the connection and connection is getting deallocated, and the inputstream then calls a method on the connection. this is _NOT_ fixable by removing the inputstream from the runloop and releasing it... dont know why... :(
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [_activeConnection removeObject:connection];
    });
}

- (void)remoteObjectConnectionConnectionEnded:(_SPLRemoteObjectConnection *)connection
{
    _SPLRemoteObjectHostConnection *hostConnection = (_SPLRemoteObjectHostConnection *)connection;

    // if everything worked correctly, we remove the completionBlock => if we have a completion block, there was an error
    if (hostConnection.completionBlock) {
        NSDictionary *userInfo = @{
                                   NSLocalizedDescriptionKey: NSLocalizedString(@"Connection to remote host failed", @"")
                                   };
        NSError *error = [NSError errorWithDomain:SPLRemoteObjectErrorDomain
                                             code:SPLRemoteObjectConnectionFailed
                                         userInfo:userInfo];

        invokeCompletionHandler(hostConnection.completionBlock, nil, error);
        hostConnection.completionBlock = nil;
    }

    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [_activeConnection removeObject:connection];
    });
}

- (void)remoteObjectConnection:(_SPLRemoteObjectConnection *)connection didReceiveDataPackage:(NSData *)dataPackage
{
    _SPLRemoteObjectHostConnection *hostConnection = (_SPLRemoteObjectHostConnection *)connection;

    if (hostConnection.completionBlock) {
        id genericCompletionBlock = hostConnection.completionBlock;
        hostConnection.completionBlock = nil;

        // check for incompatible response
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            @try {
                NSData *thisDataPackage = dataPackage;

                if (self.encryptionPolicy) {
                    thisDataPackage = [self.encryptionPolicy dataByDescryptingData:thisDataPackage];
                }
                id object = thisDataPackage.length > 0 ? [NSKeyedUnarchiver unarchiveObjectWithData:thisDataPackage] : nil;

                if ([object isKindOfClass:[_SPLNil class]]) {
                    object = nil;
                }

                if ([object isKindOfClass:[_SPLIncompatibleResponse class]]) {
                    invokeCompletionHandler(genericCompletionBlock, nil, [NSError errorWithDomain:SPLRemoteObjectErrorDomain code:SPLRemoteObjectConnectionIncompatibleProtocol userInfo:NULL]);
                } else {
                    invokeCompletionHandler(genericCompletionBlock, object, nil);
                }
            } @catch (NSException *exception) { }
        });
    }

    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [connection disconnect];
        [_activeConnection removeObject:connection];
    });
}

#pragma mark - NSObject

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@: netService: %@", [super description], self.netService];
}

- (void)dealloc
{
    [_hostBrowser removeObserver:self forKeyPath:NSStringFromSelector(@selector(userInfo)) context:SPLRemoteObjectObserver];
    [_hostBrowser removeObserver:self forKeyPath:NSStringFromSelector(@selector(resolvedNetService)) context:SPLRemoteObjectObserver];

    if (_netService.delegate == self) {
        [_netService stop];
        [_netService stopMonitoring];

        _netService.delegate = nil;
        [_netService removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

#pragma mark - Private category implementation ()

- (void)_removeQueuedConnectionBecauseOfTimeout:(_SPLRemoteObjectQueuedConnection *)queuedConnection
{
    if ([_queuedConnections containsObject:queuedConnection]) {
        NSDictionary *userInfo = (@{
                                    NSLocalizedDescriptionKey: NSLocalizedString(@"Could not reach client in given timeout", @"")
                                    });
        NSError *error = [NSError errorWithDomain:SPLRemoteObjectErrorDomain
                                             code:SPLRemoteObjectConnectionFailed
                                         userInfo:userInfo];
        invokeCompletionHandler(queuedConnection.completionBlock, nil, error);
        queuedConnection.completionBlock = nil;

        [[NSNotificationCenter defaultCenter] postNotificationName:SPLRemoteObjectNetworkOperationDidEndNotification object:nil];
        [_queuedConnections removeObject:queuedConnection];
    }
}

- (void)_forwardInvocation:(NSInvocation *)anInvocation shouldRetryIfConnectionFails:(BOOL)retry
{
    [anInvocation retainArguments];

    NSMethodSignature *methodSignature = anInvocation.methodSignature;
    NSUInteger numberOfArguments = methodSignature.numberOfArguments;

    NSString *selectorName = NSStringFromSelector(anInvocation.selector);

    // validate block argument
    {
        __unsafe_unretained id completionBlock = nil;
        [anInvocation getArgument:&completionBlock atIndex:methodSignature.numberOfArguments - 1];

        if (!completionBlock) {
            NSLog(@"the completion block argument is mandatory");
            [self doesNotRecognizeSelector:anInvocation.selector];
        }

        if (!signatureMatches([methodSignature getArgumentTypeAtIndex:methodSignature.numberOfArguments - 1], @encode(dispatch_block_t))) {
            NSLog(@"the last argument must a completion block");
            [self doesNotRecognizeSelector:anInvocation.selector];
        }

        SLBlockDescription *blockDescription = [[SLBlockDescription alloc] initWithBlock:completionBlock];
        NSMethodSignature *blockSignature = blockDescription.blockSignature;

        // block return type must be void
        if (!signatureMatches(blockSignature.methodReturnType, @encode(void))) {
            NSLog(@"completion handler can only have void return type");
            [self doesNotRecognizeSelector:anInvocation.selector];
        }

        if (blockSignature.numberOfArguments == 3) {
            if (![selectorName hasSuffix:@"WithResultsCompletionHandler:"] && ![selectorName hasSuffix:@"withResultsCompletionHandler:"]) {
                NSLog(@"method must end in (w|W)ithResultsCompletionHandler:");
                [self doesNotRecognizeSelector:anInvocation.selector];
            }

            if (!signatureMatches([blockSignature getArgumentTypeAtIndex:1], @encode(id))) {
                NSLog(@"first completion handler argument must be id typed");
                [self doesNotRecognizeSelector:anInvocation.selector];
            }

            NSString *className = [NSString stringWithFormat:@"%s", [blockSignature getArgumentTypeAtIndex:1]];
            className = [className substringWithRange:NSMakeRange(2, className.length - 3)];

            if (![NSClassFromString(className) conformsToProtocol:@protocol(NSSecureCoding)]) {
                NSLog(@"first completion handler argument must conform to NSSecureCoding");
                [self doesNotRecognizeSelector:anInvocation.selector];
            }

            NSString *errorClass = [NSString stringWithFormat:@"%s", [blockSignature getArgumentTypeAtIndex:2]];
            if (![errorClass isEqual:@"@\"NSError\""]) {
                NSLog(@"second completion handler argument must be an NSError");
                [self doesNotRecognizeSelector:anInvocation.selector];
            }
        } else if (blockSignature.numberOfArguments == 2) {
            if (![selectorName hasSuffix:@"WithCompletionHandler:"] && ![selectorName hasSuffix:@"withCompletionHandler:"]) {
                NSLog(@"method must end in (w|W)ithCompletionHandler:");
                [self doesNotRecognizeSelector:anInvocation.selector];
            }

            NSString *errorClass = [NSString stringWithFormat:@"%s", [blockSignature getArgumentTypeAtIndex:1]];
            if (![errorClass isEqual:@"@\"NSError\""]) {
                NSLog(@"completion handler argument must be an NSError");
                [self doesNotRecognizeSelector:anInvocation.selector];
            }
        } else {
            NSLog(@"completion handler not supported");
            [self doesNotRecognizeSelector:anInvocation.selector];
        }
    }

    // return type must be zero
    if (!signatureMatches(methodSignature.methodReturnType, @encode(void))) {
        NSLog(@"can only call methods with a void return type");
        [self doesNotRecognizeSelector:anInvocation.selector];
    }

    // validate arguments
    for (NSUInteger i = 2; i < numberOfArguments - 2; i++) {
        if (i > 1) {
            if (!signatureMatches([methodSignature getArgumentTypeAtIndex:i], @encode(id))) {
                NSLog(@"all arguments must be an id typed subclass");
                [self doesNotRecognizeSelector:anInvocation.selector];
            }
        }
    }

    // Now build remote invocation
    NSInvocation *remoteInvocation = [NSInvocation invocationWithMethodSignature:methodSignature];
    remoteInvocation.selector = anInvocation.selector;

    for (NSUInteger i = 2; i < numberOfArguments - 1; i++) {
        __unsafe_unretained id object = nil;
        [anInvocation getArgument:&object atIndex:i];
        [remoteInvocation setArgument:&object atIndex:i];
    }
    [remoteInvocation retainArguments];

    NSDictionary *dictionary = [remoteInvocation remoteObjectDictionaryRepresentationForProtocol:_protocol];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        __block NSData *dataPackage = [NSKeyedArchiver archivedDataWithRootObject:dictionary];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.encryptionPolicy) {
                dataPackage = [self.encryptionPolicy dataByEncryptingData:dataPackage];
            }

            if (self.netService.hostName == nil) {
                // queue data package to laster save
                __unsafe_unretained id completionBlock = nil;
                [anInvocation getArgument:&completionBlock atIndex:anInvocation.methodSignature.numberOfArguments - 1];

                _SPLRemoteObjectQueuedConnection *queuedConnection = [[_SPLRemoteObjectQueuedConnection alloc] init];
                queuedConnection.completionBlock = completionBlock;
                queuedConnection.dataPackage = dataPackage;
                queuedConnection.shouldRetryIfConnectionFails = YES;
                objc_setAssociatedObject(queuedConnection, &SPLRemoteObjectInvocationKey, anInvocation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                if (_timeoutInterval > 0.0) {
                    __weak typeof(self) weakSelf = self;
                    __weak _SPLRemoteObjectQueuedConnection *weakConnection = queuedConnection;
                    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, _timeoutInterval * NSEC_PER_SEC);

                    [[NSNotificationCenter defaultCenter] postNotificationName:SPLRemoteObjectNetworkOperationDidStartNotification object:nil];
                    dispatch_after(popTime, dispatch_get_main_queue(), ^{
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        __strong _SPLRemoteObjectQueuedConnection *strongConnection = weakConnection;
                        [strongSelf _removeQueuedConnectionBecauseOfTimeout:strongConnection];
                    });
                }

                [_queuedConnections addObject:queuedConnection];
            } else {
                __unsafe_unretained id completionBlock = nil;
                [anInvocation getArgument:&completionBlock atIndex:anInvocation.methodSignature.numberOfArguments - 1];

                _SPLRemoteObjectHostConnection *connection = [[_SPLRemoteObjectHostConnection alloc] initWithHostAddress:self.netService.hostName port:self.netService.port];
                connection.completionBlock = completionBlock;
                connection.delegate = self;
                connection.shouldRetryIfConnectionFails = retry;
                objc_setAssociatedObject(connection, &SPLRemoteObjectInvocationKey, anInvocation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                [_activeConnection addObject:connection];

                [connection connect];
                [connection sendDataPackage:dataPackage];
            }
        });
    });
}

- (BOOL)_invalidateDNSCache
{
    NSString *serviceName = [NSString stringWithFormat:@"%@.%@local.", self.name, [self.type netServiceTypeWithProtocol:self.protocol]];
    NSArray *serviceNameComponents = [serviceName componentsSeparatedByString:@"."];
    NSUInteger serviceNameComponentsCount = serviceNameComponents.count;

    NSString *fullname = [[serviceNameComponents subarrayWithRange:NSMakeRange(1, serviceNameComponentsCount - 1)] componentsJoinedByString:@"."];
    NSMutableData *recordData = [[NSMutableData alloc] init];

    for (NSString *label in serviceNameComponents) {
        const char *labelString;
        uint8_t labelStringLength;

        labelString = label.UTF8String;
        if (strlen(labelString) >= 64) {
            fprintf(stderr, "%s: label too long: %s\n", getprogname(), labelString);
            return NO;
            break;
        } else {
            // cast is safe because of length check
            labelStringLength = (uint8_t)strlen(labelString);

            [recordData appendBytes:&labelStringLength length:sizeof(labelStringLength)];
            [recordData appendBytes:labelString length:labelStringLength];
        }
    }

    if (recordData.length >= 256) {
        fprintf(stderr, "%s: record data too long\n", getprogname());
        return NO;
    }

    DNSServiceErrorType err = DNSServiceReconfirmRecord(0,
                                                        if_nametoindex("en0"),
                                                        [fullname UTF8String],
                                                        kDNSServiceType_PTR,
                                                        kDNSServiceClass_IN,
                                                        // cast is safe because of recordData length check above
                                                        (uint16_t)[recordData length],
                                                        [recordData bytes]
                                                        );
    if (err != kDNSServiceErr_NoError) {
        fprintf(stderr, "%s: reconfirm record error: %d\n", getprogname(), (int) err);
        return NO;
    }

    return YES;
}

@end

@implementation _SPLRemoteObjectQueuedConnection @end
