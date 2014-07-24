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

@interface SPLRemoteObject ()
@property (nonatomic, readonly) NSNetService *netService;
- (instancetype)initWithNetService:(NSNetService *)netService type:(NSString *)type protocol:(Protocol *)protocol;
@end



@interface SPLRemoteObjectBrowser () <NSNetServiceBrowserDelegate> {
    // not using mutableArrayValueForKey because of iOS bug forwarding addObject: to self.remoteObjects
    NSMutableArray *_remoteObjects;
}

@property (nonatomic, strong) NSNetServiceBrowser *netServiceBrowser;

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

#pragma mark - Initialization

- (id)initWithType:(NSString *)type protocol:(Protocol *)protocol
{
    if (self = [super init]) {
        _type = type;
        _protocol = protocol;

        _remoteObjects = [NSMutableArray array];

        _netServiceBrowser = [[NSNetServiceBrowser alloc] init];
        _netServiceBrowser.delegate = self;
        [_netServiceBrowser scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationDidEnterBackgroundCallback:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationWillEnterForegroundCallback:) name:UIApplicationWillEnterForegroundNotification object:nil];

        [_netServiceBrowser searchForServicesOfType:[self.type netServiceTypeWithProtocol:self.protocol] inDomain:@""];
    }
    return self;
}

#pragma mark - NSNetServiceBrowserDelegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)netService moreComing:(BOOL)moreComing
{
    SPLRemoteObject *remoteObject = [[SPLRemoteObject alloc] initWithNetService:netService type:self.type protocol:self.protocol];

    [self willChangeValueForKey:@"remoteObjects"];
    [_remoteObjects addObject:remoteObject];
    [self didChangeValueForKey:@"remoteObjects"];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didNotSearch:(NSDictionary *)errorDict
{
    NSLog(@"%@", errorDict);
    NSParameterAssert(NO);
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing
{
    NSInteger index = [self.remoteObjects indexOfObjectPassingTest:^BOOL(SPLRemoteObject *remoteObject, NSUInteger idx, BOOL *stop) {
        return remoteObject.netService == aNetService;
    }];

    if (index != NSNotFound) {
        [self willChangeValueForKey:@"remoteObjects"];
        [_remoteObjects removeObjectAtIndex:index];
        [self didChangeValueForKey:@"remoteObjects"];
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
    
    [self willChangeValueForKey:@"remoteObjects"];
    [_remoteObjects removeAllObjects];
    [self didChangeValueForKey:@"remoteObjects"];
}

#pragma mark - Private category implementation ()

@end