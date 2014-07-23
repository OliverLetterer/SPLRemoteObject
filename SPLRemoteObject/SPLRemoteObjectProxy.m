//
//  SPLRemoteObjectProxy.m
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

#import "SPLRemoteObjectProxy.h"
#import "_SPLRemoteObjectNativeSocketConnection.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#import <CFNetwork/CFNetwork.h>
#import <UIKit/UIKit.h>
#import "NSInvocation+SPLRemoteObject.h"
#import "_SPLNil.h"
#import "SPLRemoteObject.h"
#import "_SPLIncompatibleResponse.h"
#import <objc/runtime.h>

void SPLRemoteObjectProxyServerAcceptCallback(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info);



@interface SPLRemoteObjectProxy () <NSNetServiceDelegate, _SPLRemoteObjectConnectionDelegate> {
    Protocol *_protocol;
    SPLRemoteObjectErrorBlock _completionHandler;
}

@property (nonatomic, assign) CFSocketRef socket; // retained
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, strong) NSNetService *netService;

@property (nonatomic, readonly) NSString *serviceType;
@property (nonatomic, readonly) NSMutableArray *openConnections;

@property (nonatomic, readonly) BOOL isServerRunning;

- (void)startServer;
- (void)stopServer;

@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundTaskIdentifier;

- (void)_acceptConnectionFromNewNativeSocket:(CFSocketNativeHandle)nativeSocketHandle;

+ (NSData *)dataFromUserInfoDictionary:(NSDictionary *)dictionary;

@end



@implementation SPLRemoteObjectProxy

+ (NSData *)dataFromUserInfoDictionary:(NSDictionary *)dictionary
{
    NSMutableDictionary *TXTRecordDictionary = [NSMutableDictionary dictionary];

    [dictionary enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSParameterAssert([key isKindOfClass:[NSString class]]);
        NSParameterAssert([obj conformsToProtocol:@protocol(NSSecureCoding)]);

        TXTRecordDictionary[key] = [NSKeyedArchiver archivedDataWithRootObject:obj];
    }];

    return [NSNetService dataFromTXTRecordDictionary:TXTRecordDictionary];
}

#pragma mark - setters and getters

- (void)setUserInfo:(NSDictionary *)userInfo
{
    if (userInfo != _userInfo) {
        _userInfo = [userInfo copy];
        if (self.netService) {
            BOOL success = [self.netService setTXTRecordData:[SPLRemoteObjectProxy dataFromUserInfoDictionary:userInfo]];
            NSParameterAssert(success);
        }
    }
}

- (void)setIdentity:(SecIdentityRef)identity
{
    if (identity != _identity) {
        if (_identity != NULL) {
            CFRelease(_identity), _identity = NULL;
        }

        if (identity) {
            _identity = (SecIdentityRef)CFRetain(identity);
        }
    }
}

- (void)setSocket:(CFSocketRef)socket
{
    if (socket != _socket) {
        if (_socket != NULL) {
            CFRelease(_socket), _socket = NULL;
        }

        if (socket) {
            _socket = (CFSocketRef)CFRetain(socket);
        }
    }
}

- (NSString *)serviceType
{
    return [NSString stringWithFormat:@"_%@._tcp.", self.serviceName];
}

#pragma mark - Initialization

- (id)initWithServiceName:(NSString *)serviceName target:(id)target protocol:(Protocol *)protocol options:(NSDictionary *)options completionHandler:(SPLRemoteObjectErrorBlock)completionHandler
{
    if (self = [super init]) {
        _completionHandler = [completionHandler copy];
        _openConnections = [NSMutableArray array];
        _serviceName = serviceName;
        _target = target;
        _protocol = protocol;

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
            SecIdentityRef identity = (__bridge SecIdentityRef)options[SPLRemoteObjectSSLSecIdentityRef];
            NSAssert(identity, @"No identity found in SPLRemoteObjectSSLSecIdentityRef");

            _identity = (SecIdentityRef)CFRetain(identity);
        }

        NSAssert([_target conformsToProtocol:protocol], @"%@ does not conform to protocol %s", target, protocol_getName(protocol));

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationDidEnterBackgroundCallback:) name:UIApplicationDidEnterBackgroundNotification object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationWillEnterForegroundCallback:) name:UIApplicationWillEnterForegroundNotification object:nil];

        [self startServer];
    }
    return self;
}

#pragma mark - Memory management

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [self stopServer];

    if (_identity) {
        CFRelease(_identity), _identity = NULL;
    }
}

#pragma mark - NSNotificationCenter

- (void)_applicationWillEnterForegroundCallback:(NSNotification *)notification
{
    if (self.isServerRunning) {
        if (_socket == NULL) {
            [self _startServer];
        }

        if (self->_netService == NULL) {
            [self _publishService];
        }

        if (self.backgroundTaskIdentifier) {
            [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTaskIdentifier];
            self.backgroundTaskIdentifier = 0;
        }
    }
}

- (void)_applicationDidEnterBackgroundCallback:(NSNotification *)notification
{
    if (self.isServerRunning) {
        self.backgroundTaskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
            [self _stopServer];
            [self _unpublishService];

            [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTaskIdentifier];
            self.backgroundTaskIdentifier = 0;
        }];
    }
}

#pragma mark - Instance methods

- (void)startServer
{
    _isServerRunning = YES;

    [self _startServer];
    [self _publishService];
}

- (void)stopServer
{
    _isServerRunning = NO;

    [self _stopServer];
    [self _unpublishService];
}

#pragma mark - NSNetServiceDelegate

- (void)netServiceDidPublish:(NSNetService *)sender
{
    if (_completionHandler) {
        _completionHandler(nil), _completionHandler = nil;
    }
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict
{
    BOOL wasRunning = _isServerRunning && !_completionHandler;

    [self stopServer];

    if (_completionHandler) {
        NSError *error = [NSError errorWithDomain:SPLRemoteObjectErrorDomain code:0 userInfo:errorDict];
        _completionHandler(error), _completionHandler = nil;
    }

    if (wasRunning) {
        double delayInSeconds = 10.0;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [self startServer];
        });
    }

    NSLog(@"net service did not publish: %@", errorDict);
}

#pragma mark - SPLRemoteObjectConnectionDelegate

- (void)remoteObjectConnectionConnectionAttemptFailed:(_SPLRemoteObjectConnection *)connection
{
    NSLog(@"%@ connection attempt failed", self);

    NSMutableArray *optionConnections = _openConnections;
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [optionConnections removeObject:connection];
    });
}

- (void)remoteObjectConnectionConnectionEnded:(_SPLRemoteObjectConnection *)connection
{
    NSMutableArray *optionConnections = _openConnections;
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [optionConnections removeObject:connection];
    });
}

- (void)remoteObjectConnection:(_SPLRemoteObjectConnection *)connection didReceiveDataPackage:(NSData *)receivedDataPackage
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSData *dataPackage = receivedDataPackage;
        @try {
            if (_encryptionType & SPLRemoteObjectEncryptionSymmetric) {
                dataPackage = _decryptionBlock(dataPackage, _symmetricKey);
            }

            NSDictionary *dictionary = [NSKeyedUnarchiver unarchiveObjectWithData:dataPackage];
            NSInvocation *invocation __attribute__((objc_precise_lifetime)) = [NSInvocation invocationWithRemoteObjectDictionaryRepresentation:dictionary
                                                                                                                                   forProtocol:_protocol];

            void(^sendIncompatibleResponse)(void) = ^{
                NSData *responseData = responseData = [NSKeyedArchiver archivedDataWithRootObject:[[_SPLIncompatibleResponse alloc] init]];

                if (_encryptionType & SPLRemoteObjectEncryptionSymmetric) {
                    responseData = _encryptionBlock(responseData, _symmetricKey);
                }

                dispatch_async(dispatch_get_main_queue(), ^{
                    [connection sendDataPackage:responseData];
                });
            };

            if (![_target respondsToSelector:invocation.selector]) {
                return sendIncompatibleResponse();
            }

            id completionBlock = nil;

            NSString *selectorName = NSStringFromSelector(invocation.selector);
            if ([selectorName hasSuffix:@"WithResultsCompletionHandler:"] || [selectorName hasSuffix:@"withResultsCompletionHandler:"]) {
                completionBlock = ^(id returnObject, NSError *error) {
                    NSAssert([NSThread currentThread].isMainThread, @"completionBlock must be called on the main thread");

                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                        NSData *responseData = nil;
                        if (returnObject == nil) {
                            responseData = [NSKeyedArchiver archivedDataWithRootObject:[[_SPLNil alloc] init]];
                        } else {
                            NSAssert([returnObject conformsToProtocol:@protocol(NSCoding)], @"returnObject %@ must conform to NSCoding", returnObject);
                            responseData = [NSKeyedArchiver archivedDataWithRootObject:returnObject];
                        }

                        if (_encryptionType & SPLRemoteObjectEncryptionSymmetric) {
                            responseData = _encryptionBlock(responseData, _symmetricKey);
                        }

                        dispatch_async(dispatch_get_main_queue(), ^{
                            [connection sendDataPackage:responseData];
                        });
                    });
                };
            } else if (([selectorName hasSuffix:@"WithCompletionHandler:"] || [selectorName hasSuffix:@"withCompletionHandler:"])) {
                completionBlock = ^(NSError *error) {
                    NSAssert([NSThread currentThread].isMainThread, @"completionBlock must be called on the main thread");

                    NSData *emptyResponseData = [NSData data];
                    [connection sendDataPackage:emptyResponseData];
                };
            } else {
                return sendIncompatibleResponse();
            }

            [invocation setArgument:&completionBlock atIndex:invocation.methodSignature.numberOfArguments - 1];
            [invocation retainArguments];

            dispatch_sync(dispatch_get_main_queue(), ^{
                @try {
                    [invocation invokeWithTarget:_target];
                }
                @catch (NSException *exception) {
                    sendIncompatibleResponse();
                }
            });
        } @catch (NSException *exception) {
            NSLog(@"%@", exception.reason);
            NSLog(@"%@", exception.callStackSymbols);

            dispatch_async(dispatch_get_main_queue(), ^{
                [connection disconnect];
            });
        }
    });
}

#pragma mark - Private category implementation ()

- (void)_acceptConnectionFromNewNativeSocket:(CFSocketNativeHandle)nativeSocketHandle
{
    _SPLRemoteObjectNativeSocketConnection *connection = [[_SPLRemoteObjectNativeSocketConnection alloc] initWithNativeSocketHandle:nativeSocketHandle];
    connection.delegate = self;

    if (self.encryptionType & SPLRemoteObjectEncryptionSSL) {
        connection.SSLEnabled = YES;
        connection.identity = self.identity;
    }

    [_openConnections addObject:connection];
    [connection connect];
}

- (void)_startServer
{
    CFSocketContext socketContext = {0, (__bridge void *)self, NULL, NULL, NULL};

    CFSocketRef socket = CFSocketCreate(kCFAllocatorDefault,
                                        PF_INET,
                                        SOCK_STREAM,
                                        IPPROTO_TCP,
                                        kCFSocketAcceptCallBack,
                                        SPLRemoteObjectProxyServerAcceptCallback,
                                        &socketContext);
    self.socket = socket;
    CFRelease(socket);

    NSAssert(_socket != NULL, @"could not create socket");

    // getsockopt will return existing socket option value via this variable
    int reuseExistingAddress = 1;

    // Make sure that same listening socket address gets reused after every connection
    setsockopt(CFSocketGetNative(_socket), SOL_SOCKET, SO_REUSEADDR, &reuseExistingAddress, sizeof(reuseExistingAddress));

    struct sockaddr_in socketAddress;
    memset(&socketAddress, 0, sizeof(socketAddress));
    socketAddress.sin_len = sizeof(socketAddress);
    socketAddress.sin_family = AF_INET;
    socketAddress.sin_port = 0;
    socketAddress.sin_addr.s_addr = htonl(INADDR_ANY);

    NSData *socketAddressData = [NSData dataWithBytes:&socketAddress length:sizeof(socketAddress)];

    CFSocketError error = CFSocketSetAddress(_socket, (__bridge CFDataRef)socketAddressData);
    NSAssert(error == kCFSocketSuccess, @"error setting address to socket: %ld", error);

    NSData *socketAddressActualData = (__bridge_transfer NSData *)CFSocketCopyAddress(_socket);

    // Convert socket data into a usable structure
    struct sockaddr_in socketAddressActual;
    memcpy(&socketAddressActual, [socketAddressActualData bytes], [socketAddressActualData length]);

    _port = ntohs(socketAddressActual.sin_port);

    CFRunLoopRef currentRunLoop = CFRunLoopGetCurrent();
    CFRunLoopSourceRef runLoopSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socket, 0);
    CFRunLoopAddSource(currentRunLoop, runLoopSource, kCFRunLoopCommonModes);
    CFRelease(runLoopSource);
}

- (void)_publishService
{
    _netService = [[NSNetService alloc] initWithDomain:@"" type:self.serviceType name:self.serviceName port:_port];
    [_netService scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    _netService.delegate = self;
    if (self.userInfo) {
        BOOL success = [_netService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:self.userInfo]];
        NSParameterAssert(success);
    }
	[_netService publish];
}

- (void)_stopServer
{
    if (_socket != NULL) {
        CFSocketInvalidate(_socket);
        self.socket = NULL;
    }
}

- (void)_unpublishService
{
    [_netService stop];
    [_netService removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    _netService = nil;
}

@end

void SPLRemoteObjectProxyServerAcceptCallback(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    SPLRemoteObjectProxy *host = (__bridge SPLRemoteObjectProxy *)info;

    if (type != kCFSocketAcceptCallBack) {
        return;
    }

    CFSocketNativeHandle nativeSocketHandle = *((CFSocketNativeHandle *)data);

    [host _acceptConnectionFromNewNativeSocket:nativeSocketHandle];
}
