//
//  SPLRemoteObjectBrowser.m
//  Pods
//
//  Created by Oliver Letterer on 23.07.14.
//  Copyright 2014 __MyCompanyName__. All rights reserved.
//

#import "SPLRemoteObjectBrowser.h"
#import "SPLRemoteObject.h"
#import "NSString+SPLRemoteObject.h"
#import <SPLNetService.h>
#import <SPLNetServiceBrowser.h>

@interface SPLRemoteObject ()
@property (nonatomic, readonly) SPLNetService *netService;
- (instancetype)initWithNetService:(SPLNetService *)netService type:(NSString *)type protocol:(Protocol *)protocol;
@end



@interface SPLRemoteObjectBrowser () <SPLNetServiceBrowserDelegate>

@property (nonatomic, readonly) NSMutableArray *mutableRemoteObjects;
@property (nonatomic, strong) SPLNetServiceBrowser *netServiceBrowser;

@end





@implementation SPLRemoteObjectBrowser

+ (void)initialize
{
    if (self != [SPLRemoteObjectBrowser class]) {
        return;
    }

    NSParameterAssert([SPLRemoteObject instancesRespondToSelector:@selector(initWithNetService:type:protocol:)]);
    NSParameterAssert([SPLRemoteObject instancesRespondToSelector:@selector(netService)]);
}

#pragma mark - setters and getters

- (NSMutableArray *)mutableRemoteObjects
{
    return [self mutableArrayValueForKey:NSStringFromSelector(@selector(remoteObjects))];
}

#pragma mark - Initialization

- (instancetype)initWithType:(NSString *)type protocol:(Protocol *)protocol encryptionPolicy:(id<SPLRemoteObjectEncryptionPolicy>)encryptionPolicy
{
    if (self = [super init]) {
        _type = type;
        _protocol = protocol;
        _encryptionPolicy = encryptionPolicy;

        _remoteObjects = [NSMutableArray array];

        _netServiceBrowser = [[SPLNetServiceBrowser alloc] init];
        _netServiceBrowser.delegate = self;
        [_netServiceBrowser scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationDidEnterBackgroundCallback:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationWillEnterForegroundCallback:) name:UIApplicationWillEnterForegroundNotification object:nil];

        [_netServiceBrowser searchForServicesOfType:[self.type netServiceTypeWithProtocol:self.protocol] inDomain:@""];
    }
    return self;
}

- (void)dealloc
{
    _netServiceBrowser.delegate = nil;
    [_netServiceBrowser removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - SPLNetServiceBrowserDelegate

- (void)netServiceBrowser:(SPLNetServiceBrowser *)netServiceBrowser didFindService:(SPLNetService *)netService moreComing:(BOOL)moreComing
{
    SPLRemoteObject *remoteObject = [[SPLRemoteObject alloc] initWithNetService:netService type:self.type protocol:self.protocol];
    remoteObject.encryptionPolicy = self.encryptionPolicy;
    [self.mutableRemoteObjects addObject:remoteObject];
}

- (void)netServiceBrowser:(SPLNetServiceBrowser *)aNetServiceBrowser didNotSearch:(NSDictionary *)errorDict
{
    NSLog(@"%@", errorDict);
    NSParameterAssert(NO);
}

- (void)netServiceBrowser:(SPLNetServiceBrowser *)aNetServiceBrowser didRemoveService:(SPLNetService *)aNetService moreComing:(BOOL)moreComing
{
    NSInteger index = [self.remoteObjects indexOfObjectPassingTest:^BOOL(SPLRemoteObject *remoteObject, NSUInteger idx, BOOL *stop) {
        return remoteObject.netService == aNetService;
    }];

    if (index != NSNotFound) {
        [self.mutableRemoteObjects removeObjectAtIndex:index];
    }
}

#pragma mark - NSNotificationCenter

- (void)_applicationWillEnterForegroundCallback:(NSNotification *)notification
{
    [self.netServiceBrowser searchForServicesOfType:[self.type netServiceTypeWithProtocol:self.protocol] inDomain:@""];
}

- (void)_applicationDidEnterBackgroundCallback:(NSNotification *)notification
{
    [self.netServiceBrowser stop];
    [self.mutableRemoteObjects removeAllObjects];
}

#pragma mark - Private category implementation ()

@end
