//
//  SLRemoteObject.m
//  SLRemoteObject
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

#import "SLRemoteObject.h"
#import "_SLRemoteObjectProxyBrowser.h"
#import "NSInvocation+SLRemoteObject.h"
#import "_SLRemoteObjectHostConnection.h"
#import "SLBlockDescription.h"
#import "_SLNil.h"
#import "_SLIncompatibleResponse.h"
#import <objc/runtime.h>
#import <dns_sd.h>
#import <net/if.h>
#import <AssertMacros.h>

char * const SLRemoteObjectInvocationKey;

static BOOL signatureMatches(const char *signature1, const char *signature2)
{
    return signature1[0] == signature2[0];
}

@interface _SLRemoteObjectQueuedConnection : NSObject

@property (nonatomic, copy) id completionBlock;
@property (nonatomic, strong) NSMethodSignature *remoteMethodSignature;
@property (nonatomic, strong) NSData *dataPackage;
@property (nonatomic, assign) BOOL shouldRetryIfConnectionFails;

@end

@interface _SLRemoteObjectConnection (SLRemoteObject)
@property (nonatomic, assign) BOOL shouldRetryIfConnectionFails;
@end

@implementation _SLRemoteObjectConnection (SLRemoteObject)

- (BOOL)shouldRetryIfConnectionFails
{
    return [objc_getAssociatedObject(self, @selector(shouldRetryIfConnectionFails)) boolValue];
}

- (void)setShouldRetryIfConnectionFails:(BOOL)shouldRetryIfConnectionFails
{
    objc_setAssociatedObject(self, @selector(shouldRetryIfConnectionFails), @(shouldRetryIfConnectionFails), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end



@interface SLRemoteObject () <_SLRemoteObjectConnectionDelegate, _SLRemoteObjectProxyBrowserDelegate> {
    Protocol *_protocol;
    _SLRemoteObjectProxyBrowser *_hostBrowser;
    NSMutableArray *_activeConnection;

    NSMutableArray *_queuedConnections;
}

@property (nonatomic, readonly) NSString *serviceType;

- (id)initWithServiceName:(NSString *)serviceName protocol:(Protocol *)protocol options:(NSDictionary *)options;

@property (nonatomic, assign) SLRemoteObjectReachabilityStatus reachabilityStatus;

@end



@implementation SLRemoteObject

#pragma mark - setters and getters

- (NSString *)serviceType
{
    return [NSString stringWithFormat:@"_%@._tcp.", self.serviceName];
}

#pragma mark - Initialization

+ (id)remoteObjectWithServiceName:(NSString *)serviceName protocol:(Protocol *)protocol options:(NSDictionary *)options
{
    return [[SLRemoteObject alloc] initWithServiceName:serviceName protocol:protocol options:options];
}

- (id)initWithServiceName:(NSString *)serviceName protocol:(Protocol *)protocol options:(NSDictionary *)options
{
    NSParameterAssert(protocol);
    NSParameterAssert(serviceName);

    if (self = [super init]) {
        _protocol = protocol;
        _serviceName = serviceName;

        _encryptionType = [options[SLRemoteObjectEncryptionType] unsignedIntegerValue];

        if (_encryptionType & SLRemoteObjectEncryptionSymmetric) {
            _encryptionBlock = options[SLRemoteObjectSymmetricEncryptionBlock];
            _decryptionBlock = options[SLRemoteObjectSymmetricDecryptionBlock];
            _symmetricKey = options[SLRemoteObjectSymmetricKey];

            NSAssert(_encryptionBlock, @"No encryption block found in SLRemoteObjectSymmetricEncryptionBlock");
            NSAssert(_decryptionBlock, @"No decryption block found in SLRemoteObjectSymmetricDecryptionBlock");
            NSAssert(_symmetricKey, @"No symmetric key found in SLRemoteObjectSymmetricKey");
        }

        if (_encryptionType & SLRemoteObjectEncryptionSSL) {
            _peerDomainName = options[SLRemoteObjectSSLPeerDomainName];
        }

        _activeConnection = [NSMutableArray array];
        _queuedConnections = [NSMutableArray array];

        _hostBrowser = [[_SLRemoteObjectProxyBrowser alloc] initWithServiceType:self.serviceType];
        _hostBrowser.delegate = self;
        [_hostBrowser startDiscoveringRemoteObjectHosts];
    }
    return self;
}

#pragma mark - NSObject

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    struct objc_method_description methodDescription = protocol_getMethodDescription(_protocol, aSelector, NO, YES);

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

#pragma mark - _SLRemoteObjectConnectionDelegate

- (void)remoteObjectConnectionConnectionAttemptFailed:(_SLRemoteObjectConnection *)connection
{
    _SLRemoteObjectHostConnection *hostConnection = (_SLRemoteObjectHostConnection *)connection;

    NSInvocation *invocation = objc_getAssociatedObject(hostConnection, &SLRemoteObjectInvocationKey);
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
        NSError *error = [NSError errorWithDomain:SLRemoteObjectErrorDomain
                                             code:SLRemoteObjectConnectionFailed
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

- (void)remoteObjectConnectionConnectionEnded:(_SLRemoteObjectConnection *)connection
{
    _SLRemoteObjectHostConnection *hostConnection = (_SLRemoteObjectHostConnection *)connection;

    // if everything worked correctly, we remove the completionBlock => if we have a completion block, there was an error
    if (hostConnection.completionBlock) {
        NSDictionary *userInfo = (@{
                                    NSLocalizedDescriptionKey: NSLocalizedString(@"Connection to remote host failed", @"")
                                    });
        NSError *error = [NSError errorWithDomain:SLRemoteObjectErrorDomain
                                             code:SLRemoteObjectConnectionFailed
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

- (void)remoteObjectConnection:(_SLRemoteObjectConnection *)connection didReceiveDataPackage:(NSData *)dataPackage
{
    _SLRemoteObjectHostConnection *hostConnection = (_SLRemoteObjectHostConnection *)connection;

    if (hostConnection.completionBlock) {
        // check for incompatible response
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            if (dataPackage.length > 0) {
                NSData *thisDataPackage = dataPackage;
                if (_encryptionType & SLRemoteObjectEncryptionSymmetric) {
                    thisDataPackage = _decryptionBlock(thisDataPackage, _symmetricKey);
                }

                id object = [NSKeyedUnarchiver unarchiveObjectWithData:thisDataPackage];

                if ([object isKindOfClass:[_SLIncompatibleResponse class]]) {
                    if (signatureMatches(hostConnection.remoteMethodSignature.methodReturnType, @encode(void))) {
                        void(^completionBlock)(NSError *error) = hostConnection.completionBlock;

                        dispatch_async(dispatch_get_main_queue(), ^{
                            completionBlock([NSError errorWithDomain:SLRemoteObjectErrorDomain code:SLRemoteObjectConnectionIncompatibleProtocol userInfo:NULL]);
                        });
                    } else if (signatureMatches(hostConnection.remoteMethodSignature.methodReturnType, @encode(id))) {
                        void(^completionBlock)(id object, NSError *error) = hostConnection.completionBlock;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completionBlock(nil, [NSError errorWithDomain:SLRemoteObjectErrorDomain code:SLRemoteObjectConnectionIncompatibleProtocol userInfo:NULL]);
                        });
                    }

                    hostConnection.completionBlock = nil;
                    return;
                }
            }

            if (signatureMatches(hostConnection.remoteMethodSignature.methodReturnType, @encode(void))) {
                void(^completionBlock)(NSError *error) = hostConnection.completionBlock;

                dispatch_async(dispatch_get_main_queue(), ^{
                    completionBlock(nil);
                });
            } else if (signatureMatches(hostConnection.remoteMethodSignature.methodReturnType, @encode(id))) {
                @try {
                    id object = nil;
                    NSData *thisDataPackage = dataPackage;

                    if (_encryptionType & SLRemoteObjectEncryptionSymmetric) {
                        thisDataPackage = _decryptionBlock(thisDataPackage, _symmetricKey);
                    }
                    object = [NSKeyedUnarchiver unarchiveObjectWithData:thisDataPackage];

                    if ([object isKindOfClass:[_SLNil class]]) {
                        object = nil;
                    }

                    void(^completionBlock)(id object, NSError *error) = hostConnection.completionBlock;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completionBlock(object, nil);
                    });
                } @catch (NSException *exception) { }
            }

            hostConnection.completionBlock = nil;
        });
    }

    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [connection disconnect];
        [_activeConnection removeObject:connection];
    });
}

#pragma mark - _SLRemoteObjectProxyBrowserDelegate

- (void)remoteObjectHostBrowserDidChangeNumberOfResolvedNetServices:(_SLRemoteObjectProxyBrowser *)remoteObjectHostBrowser
{
    self.reachabilityStatus = remoteObjectHostBrowser.resolvedNetServices.count > 0 ? SLRemoteObjectReachabilityStatusAvailable : SLRemoteObjectReachabilityStatusUnavailable;

    if (remoteObjectHostBrowser.resolvedNetServices.count > 0) {
        for (_SLRemoteObjectQueuedConnection *queuedConnection in _queuedConnections) {
            NSInvocation *invocation = objc_getAssociatedObject(queuedConnection, &SLRemoteObjectInvocationKey);
            NSParameterAssert(invocation);

            // -1 operation from queue
            [[NSNotificationCenter defaultCenter] postNotificationName:SLRemoteObjectNetworkOperationDidEndNotification object:nil];

            for (NSNetService *netService in _hostBrowser.resolvedNetServices) {
                _SLRemoteObjectHostConnection *connection = [[_SLRemoteObjectHostConnection alloc] initWithHostAddress:netService.hostName port:netService.port];
                connection.completionBlock = queuedConnection.completionBlock;
                connection.delegate = self;
                connection.remoteMethodSignature = queuedConnection.remoteMethodSignature;
                connection.shouldRetryIfConnectionFails = queuedConnection.shouldRetryIfConnectionFails;
                objc_setAssociatedObject(connection, &SLRemoteObjectInvocationKey, invocation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                if (self.encryptionType & SLRemoteObjectEncryptionSSL) {
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

- (void)_removeQueuedConnectionBecauseOfTimeout:(_SLRemoteObjectQueuedConnection *)queuedConnection
{
    if ([_queuedConnections containsObject:queuedConnection]) {
        NSDictionary *userInfo = (@{
                                    NSLocalizedDescriptionKey: NSLocalizedString(@"Could not reach client in given timeout", @"")
                                    });
        NSError *error = [NSError errorWithDomain:SLRemoteObjectErrorDomain
                                             code:SLRemoteObjectConnectionFailed
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

        [[NSNotificationCenter defaultCenter] postNotificationName:SLRemoteObjectNetworkOperationDidEndNotification object:nil];
        [_queuedConnections removeObject:queuedConnection];
    }
}

- (void)_forwardInvocation:(NSInvocation *)anInvocation shouldRetryIfConnectionFails:(BOOL)retry
{
    [anInvocation retainArguments];

    NSMethodSignature *methodSignature = anInvocation.methodSignature;
    NSUInteger numberOfArguments = methodSignature.numberOfArguments;

    NSString *selectorName = NSStringFromSelector(anInvocation.selector);

    // only accept methods with completion handler
    if (![selectorName hasSuffix:@"withCompletionHandler:"] && ![selectorName hasSuffix:@"WithCompletionHandler:"]) {
        NSLog(@"can only call methods with a return handler");
        [self doesNotRecognizeSelector:anInvocation.selector];
    }

    // return type must be zero
    if (!signatureMatches(methodSignature.methodReturnType, @encode(void))) {
        NSLog(@"can only call methods with a void return type. use method with return handler");
        [self doesNotRecognizeSelector:anInvocation.selector];
    }

    SEL remoteSelector = NULL;

    NSString *possibleSuffix1 = @"withCompletionHandler:";
    NSString *possibleSuffix2 = @"WithCompletionHandler:";
    if ([selectorName hasSuffix:possibleSuffix1]) {
        NSString *remoteSelectorName = [selectorName stringByReplacingOccurrencesOfString:possibleSuffix1
                                                                               withString:@""
                                                                                  options:NSLiteralSearch
                                                                                    range:NSMakeRange(selectorName.length - possibleSuffix1.length, possibleSuffix1.length)];
        remoteSelector = NSSelectorFromString(remoteSelectorName);
    } else if ([selectorName hasSuffix:possibleSuffix2]) {
        NSString *remoteSelectorName = [selectorName stringByReplacingOccurrencesOfString:possibleSuffix2
                                                                               withString:@""
                                                                                  options:NSLiteralSearch
                                                                                    range:NSMakeRange(selectorName.length - possibleSuffix2.length, possibleSuffix2.length)];
        remoteSelector = NSSelectorFromString(remoteSelectorName);
    }

    if (remoteSelector == NULL) {
        NSLog(@"protocol selector %@ must have a pendend without completion handler which will be executed on remote proxy", selectorName);
        [self doesNotRecognizeSelector:anInvocation.selector];
    }

    struct objc_method_description remoteMethodDescription = protocol_getMethodDescription(_protocol, remoteSelector, YES, YES);

    if (remoteMethodDescription.types == NULL) {
        NSLog(@"selector %@ in protocol %s not found", NSStringFromSelector(remoteSelector), protocol_getName(_protocol));
        [self doesNotRecognizeSelector:anInvocation.selector];
    }

    NSMethodSignature *remoteMethodSignature = [NSMethodSignature signatureWithObjCTypes:remoteMethodDescription.types];

    // validate arguments
    for (NSUInteger i = 0; i < numberOfArguments; i++) {
        if (i < numberOfArguments - 1) {
            if (!signatureMatches([methodSignature getArgumentTypeAtIndex:i], [remoteMethodSignature getArgumentTypeAtIndex:i])) {
                NSLog(@"argument %lu on host does not match argument on remote", (unsigned long)i);
                [self doesNotRecognizeSelector:anInvocation.selector];
            }
        }

        if (i == numberOfArguments - 1) {
            __unsafe_unretained id completionBlock = nil;
            [anInvocation getArgument:&completionBlock atIndex:i];
            SLBlockDescription *blockDescription = [[SLBlockDescription alloc] initWithBlock:completionBlock];
            NSMethodSignature *blockSignature = blockDescription.blockSignature;

            // block return type must be void
            if (!signatureMatches(blockSignature.methodReturnType, @encode(void))) {
                NSLog(@"completion handler can only have void return type");
                [self doesNotRecognizeSelector:anInvocation.selector];
            }

            if (signatureMatches(remoteMethodSignature.methodReturnType, @encode(void))) {
                // remote method returns void
                if (blockSignature.numberOfArguments != 2) {
                    NSLog(@"completion handler can only have an NSError parameter");
                    [self doesNotRecognizeSelector:anInvocation.selector];
                }

                if (!signatureMatches([blockSignature getArgumentTypeAtIndex:1], @encode(id))) {
                    NSLog(@"completion handler can only have an NSError parameter");
                    [self doesNotRecognizeSelector:anInvocation.selector];
                }
            } else if (signatureMatches(remoteMethodSignature.methodReturnType, @encode(id))) {
                // object return type
                if (blockSignature.numberOfArguments != 3) {
                    NSLog(@"completion handler can only have a result and NSError parameter");
                    [self doesNotRecognizeSelector:anInvocation.selector];
                }

                if (!signatureMatches([blockSignature getArgumentTypeAtIndex:1], @encode(id))) {
                    NSLog(@"completion handler can only have a result and NSError parameter");
                    [self doesNotRecognizeSelector:anInvocation.selector];
                }

                if (!signatureMatches([blockSignature getArgumentTypeAtIndex:2], @encode(id))) {
                    NSLog(@"completion handler can only have a result and NSError parameter");
                    [self doesNotRecognizeSelector:anInvocation.selector];
                }
            } else {
                // other return type
                NSLog(@"remote methods can only return void or an id type object");
                [self doesNotRecognizeSelector:anInvocation.selector];
            }
        } else {
            // every argument after self and _cmd must be of id type
            if (i > 1) {
                if (!signatureMatches([methodSignature getArgumentTypeAtIndex:i], @encode(id))) {
                    NSLog(@"all arguments must be an NSObject subclass");
                    [self doesNotRecognizeSelector:anInvocation.selector];
                }
            }
        }
    }

    // Now build remote invocation
    NSInvocation *remoteInvocation = [NSInvocation invocationWithMethodSignature:remoteMethodSignature];
    remoteInvocation.selector = remoteSelector;

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
            if (_encryptionType & SLRemoteObjectEncryptionSymmetric) {
                dataPackage = _encryptionBlock(dataPackage, _symmetricKey);
            }

            if (_hostBrowser.resolvedNetServices.count == 0) {
                // queue data package to laster save
                __unsafe_unretained id completionBlock = nil;
                [anInvocation getArgument:&completionBlock atIndex:anInvocation.methodSignature.numberOfArguments - 1];

                _SLRemoteObjectQueuedConnection *queuedConnection = [[_SLRemoteObjectQueuedConnection alloc] init];
                queuedConnection.completionBlock = completionBlock;
                queuedConnection.remoteMethodSignature = remoteMethodSignature;
                queuedConnection.dataPackage = dataPackage;
                queuedConnection.shouldRetryIfConnectionFails = YES;
                objc_setAssociatedObject(queuedConnection, &SLRemoteObjectInvocationKey, anInvocation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                if (_timeoutInterval > 0.0) {
                    __weak typeof(self) weakSelf = self;
                    __weak _SLRemoteObjectQueuedConnection *weakConnection = queuedConnection;
                    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, _timeoutInterval * NSEC_PER_SEC);

                    [[NSNotificationCenter defaultCenter] postNotificationName:SLRemoteObjectNetworkOperationDidStartNotification object:nil];
                    dispatch_after(popTime, dispatch_get_main_queue(), ^{
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        __strong _SLRemoteObjectQueuedConnection *strongConnection = weakConnection;
                        [strongSelf _removeQueuedConnectionBecauseOfTimeout:strongConnection];
                    });
                }

                [_queuedConnections addObject:queuedConnection];
            } else {
                for (NSNetService *netService in _hostBrowser.resolvedNetServices) {
                    __unsafe_unretained id completionBlock = nil;
                    [anInvocation getArgument:&completionBlock atIndex:anInvocation.methodSignature.numberOfArguments - 1];

                    _SLRemoteObjectHostConnection *connection = [[_SLRemoteObjectHostConnection alloc] initWithHostAddress:netService.hostName port:netService.port];
                    connection.completionBlock = completionBlock;
                    connection.delegate = self;
                    connection.remoteMethodSignature = remoteMethodSignature;
                    connection.shouldRetryIfConnectionFails = YES;
                    objc_setAssociatedObject(connection, &SLRemoteObjectInvocationKey, anInvocation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                    if (self.encryptionType & SLRemoteObjectEncryptionSSL) {
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
    
}

#pragma mark - Private category implementation ()

@end

@implementation _SLRemoteObjectQueuedConnection @end
