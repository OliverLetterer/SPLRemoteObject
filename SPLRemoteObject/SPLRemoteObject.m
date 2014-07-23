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

char * const SPLRemoteObjectInvocationKey;

static BOOL signatureMatches(const char *signature1, const char *signature2)
{
    return signature1[0] == signature2[0];
}

@interface _SPLRemoteObjectQueuedConnection : NSObject

@property (nonatomic, copy) id completionBlock;
@property (nonatomic, strong) NSMethodSignature *remoteMethodSignature;
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



static void * SPLRemoteObjectUserInfoObserver = &SPLRemoteObjectUserInfoObserver;

@interface SPLRemoteObject () <_SPLRemoteObjectConnectionDelegate, _SPLRemoteObjectProxyBrowserDelegate> {
    Protocol *_protocol;
    _SPLRemoteObjectProxyBrowser *_hostBrowser;
    NSMutableArray *_activeConnection;

    NSMutableArray *_queuedConnections;
}

@property (nonatomic, readonly) NSString *serviceType;
@property (nonatomic, copy) NSDictionary *userInfo;

- (id)initWithServiceName:(NSString *)serviceName protocol:(Protocol *)protocol options:(NSDictionary *)options;

@property (nonatomic, assign) SPLRemoteObjectReachabilityStatus reachabilityStatus;

@end



@implementation SPLRemoteObject

#pragma mark - setters and getters

- (NSString *)serviceType
{
    return [NSString stringWithFormat:@"_%@._tcp.", self.serviceName];
}

#pragma mark - Initialization

+ (id)remoteObjectWithServiceName:(NSString *)serviceName protocol:(Protocol *)protocol options:(NSDictionary *)options
{
    return [[SPLRemoteObject alloc] initWithServiceName:serviceName protocol:protocol options:options];
}

- (id)initWithServiceName:(NSString *)serviceName protocol:(Protocol *)protocol options:(NSDictionary *)options
{
    NSParameterAssert(protocol);
    NSParameterAssert(serviceName);

    if (self = [super init]) {
        _protocol = protocol;
        _serviceName = serviceName;

        _encryptionType = [options[SPLRemoteObjectEncryptionType] unsignedIntegerValue];

        if (_encryptionType & SPLRemoteObjectEncryptionSymmetric) {
            _encryptionBlock = options[SPLRemoteObjectSymmetricEncryptionBlock];
            _decryptionBlock = options[SPLRemoteObjectSymmetricDecryptionBlock];
            _symmetricKey = options[SPLRemoteObjectSymmetricKey];

            NSAssert(_encryptionBlock, @"No encryption block found in SPLRemoteObjectSymmetricEncryptionBlock");
            NSAssert(_decryptionBlock, @"No decryption block found in SPLRemoteObjectSymmetricDecryptionBlock");
            NSAssert(_symmetricKey, @"No symmetric key found in SPLRemoteObjectSymmetricKey");
        }

        if (_encryptionType & SPLRemoteObjectEncryptionSSL) {
            _peerDomainName = options[SPLRemoteObjectSSLPeerDomainName];
        }

        _activeConnection = [NSMutableArray array];
        _queuedConnections = [NSMutableArray array];

        _hostBrowser = [[_SPLRemoteObjectProxyBrowser alloc] initWithServiceType:self.serviceType];
        [_hostBrowser addObserver:self forKeyPath:NSStringFromSelector(@selector(userInfo)) options:NSKeyValueObservingOptionNew context:SPLRemoteObjectUserInfoObserver];
        _hostBrowser.delegate = self;
        [_hostBrowser startDiscoveringRemoteObjectHosts];
    }
    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == SPLRemoteObjectUserInfoObserver) {
        self.userInfo = _hostBrowser.userInfo;
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
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
        NSDictionary *userInfo = (@{
                                    NSLocalizedDescriptionKey: NSLocalizedString(@"Connection to remote host failed", @"")
                                    });
        NSError *error = [NSError errorWithDomain:SPLRemoteObjectErrorDomain
                                             code:SPLRemoteObjectConnectionFailed
                                         userInfo:userInfo];

        if (signatureMatches(hostConnection.remoteMethodSignature.methodReturnType, @encode(void))) {
            void(^completionBlock)(NSError *error) = hostConnection.completionBlock;
            completionBlock(error);
        } else if (signatureMatches(hostConnection.remoteMethodSignature.methodReturnType, @encode(id))) {
            void(^completionBlock)(id object, NSError *error) = hostConnection.completionBlock;
            completionBlock(nil, error);
        }
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
        NSDictionary *userInfo = (@{
                                    NSLocalizedDescriptionKey: NSLocalizedString(@"Connection to remote host failed", @"")
                                    });
        NSError *error = [NSError errorWithDomain:SPLRemoteObjectErrorDomain
                                             code:SPLRemoteObjectConnectionFailed
                                         userInfo:userInfo];

        if (signatureMatches(hostConnection.remoteMethodSignature.methodReturnType, @encode(void))) {
            void(^completionBlock)(NSError *error) = hostConnection.completionBlock;
            completionBlock(error);
        } else if (signatureMatches(hostConnection.remoteMethodSignature.methodReturnType, @encode(id))) {
            void(^completionBlock)(id object, NSError *error) = hostConnection.completionBlock;
            completionBlock(nil, error);
        }
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
            SLBlockDescription *blockDescription = [[SLBlockDescription alloc] initWithBlock:genericCompletionBlock];
            @try {
                NSData *thisDataPackage = dataPackage;

                if (_encryptionType & SPLRemoteObjectEncryptionSymmetric) {
                    thisDataPackage = _decryptionBlock(thisDataPackage, _symmetricKey);
                }
                id object = thisDataPackage.length > 0 ? [NSKeyedUnarchiver unarchiveObjectWithData:thisDataPackage] : nil;

                if ([object isKindOfClass:[_SPLNil class]]) {
                    object = nil;
                }

                void(^invokeCompletionHandler)(id object, NSError *error) = ^(id object, NSError *error) {
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

                        dispatch_async(dispatch_get_main_queue(), ^{
                            completionBlock(object, error);
                        });
                    } else {
                        void(^completionBlock)(NSError *error) = genericCompletionBlock;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completionBlock(error);
                        });
                    }
                };

                if ([object isKindOfClass:[_SPLIncompatibleResponse class]]) {
                    invokeCompletionHandler(nil, [NSError errorWithDomain:SPLRemoteObjectErrorDomain code:SPLRemoteObjectConnectionIncompatibleProtocol userInfo:NULL]);
                } else {
                    invokeCompletionHandler(object, nil);
                }
            } @catch (NSException *exception) { }
        });
    }

    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [connection disconnect];
        [_activeConnection removeObject:connection];
    });
}

#pragma mark - _SPLRemoteObjectProxyBrowserDelegate

- (void)remoteObjectHostBrowserDidChangeNumberOfResolvedNetServices:(_SPLRemoteObjectProxyBrowser *)remoteObjectHostBrowser
{
    self.reachabilityStatus = remoteObjectHostBrowser.resolvedNetServices.count > 0 ? SPLRemoteObjectReachabilityStatusAvailable : SPLRemoteObjectReachabilityStatusUnavailable;

    if (remoteObjectHostBrowser.resolvedNetServices.count > 0) {
        for (_SPLRemoteObjectQueuedConnection *queuedConnection in _queuedConnections) {
            NSInvocation *invocation = objc_getAssociatedObject(queuedConnection, &SPLRemoteObjectInvocationKey);
            NSParameterAssert(invocation);

            // -1 operation from queue
            [[NSNotificationCenter defaultCenter] postNotificationName:SPLRemoteObjectNetworkOperationDidEndNotification object:nil];

            for (NSNetService *netService in _hostBrowser.resolvedNetServices) {
                _SPLRemoteObjectHostConnection *connection = [[_SPLRemoteObjectHostConnection alloc] initWithHostAddress:netService.hostName port:netService.port];
                connection.completionBlock = queuedConnection.completionBlock;
                connection.delegate = self;
                connection.remoteMethodSignature = queuedConnection.remoteMethodSignature;
                connection.shouldRetryIfConnectionFails = queuedConnection.shouldRetryIfConnectionFails;
                objc_setAssociatedObject(connection, &SPLRemoteObjectInvocationKey, invocation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                if (self.encryptionType & SPLRemoteObjectEncryptionSSL) {
                    connection.SSLEnabled = YES;
                    connection.peerDomainName = self.peerDomainName;
                }

                [_activeConnection addObject:connection];

                [connection connect];
                [connection sendDataPackage:queuedConnection.dataPackage];
            }
        }

        [_queuedConnections removeAllObjects];
    }
}

- (void)_removeQueuedConnectionBecauseOfTimeout:(_SPLRemoteObjectQueuedConnection *)queuedConnection
{
    if ([_queuedConnections containsObject:queuedConnection]) {
        NSDictionary *userInfo = (@{
                                    NSLocalizedDescriptionKey: NSLocalizedString(@"Could not reach client in given timeout", @"")
                                    });
        NSError *error = [NSError errorWithDomain:SPLRemoteObjectErrorDomain
                                             code:SPLRemoteObjectConnectionFailed
                                         userInfo:userInfo];
        if (queuedConnection.completionBlock) {
            if (signatureMatches(queuedConnection.remoteMethodSignature.methodReturnType, @encode(void))) {
                void(^completionBlock)(NSError *error) = queuedConnection.completionBlock;
                completionBlock(error);
            } else if (signatureMatches(queuedConnection.remoteMethodSignature.methodReturnType, @encode(id))) {
                void(^completionBlock)(id object, NSError *error) = queuedConnection.completionBlock;
                completionBlock(nil, error);
            }
        }

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
            if (_encryptionType & SPLRemoteObjectEncryptionSymmetric) {
                dataPackage = _encryptionBlock(dataPackage, _symmetricKey);
            }

            if (_hostBrowser.resolvedNetServices.count == 0) {
                // queue data package to laster save
                __unsafe_unretained id completionBlock = nil;
                [anInvocation getArgument:&completionBlock atIndex:anInvocation.methodSignature.numberOfArguments - 1];

                _SPLRemoteObjectQueuedConnection *queuedConnection = [[_SPLRemoteObjectQueuedConnection alloc] init];
                queuedConnection.completionBlock = completionBlock;
                queuedConnection.remoteMethodSignature = methodSignature;
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
                for (NSNetService *netService in _hostBrowser.resolvedNetServices) {
                    __unsafe_unretained id completionBlock = nil;
                    [anInvocation getArgument:&completionBlock atIndex:anInvocation.methodSignature.numberOfArguments - 1];

                    _SPLRemoteObjectHostConnection *connection = [[_SPLRemoteObjectHostConnection alloc] initWithHostAddress:netService.hostName port:netService.port];
                    connection.completionBlock = completionBlock;
                    connection.delegate = self;
                    connection.remoteMethodSignature = methodSignature;
                    connection.shouldRetryIfConnectionFails = YES;
                    objc_setAssociatedObject(connection, &SPLRemoteObjectInvocationKey, anInvocation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                    if (self.encryptionType & SPLRemoteObjectEncryptionSSL) {
                        connection.SSLEnabled = YES;
                        connection.peerDomainName = self.peerDomainName;
                    }

                    [_activeConnection addObject:connection];

                    [connection connect];
                    [connection sendDataPackage:dataPackage];
                }
            }
        });
    });
}

- (BOOL)_invalidateDNSCache
{
    NSString *serviceName = [NSString stringWithFormat:@"%@.%@local.", self.serviceName, self.serviceType];
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

#pragma mark - NSObject

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@: <service: %@, %lu hosts found: %@>", [super description], self.serviceName, (unsigned long)_hostBrowser.resolvedNetServices.count, _hostBrowser.resolvedNetServices];
}

#pragma mark - Memory management

- (void)dealloc
{
    [_hostBrowser removeObserver:self forKeyPath:NSStringFromSelector(@selector(userInfo)) context:SPLRemoteObjectUserInfoObserver];
}

#pragma mark - Private category implementation ()

@end

@implementation _SPLRemoteObjectQueuedConnection @end
