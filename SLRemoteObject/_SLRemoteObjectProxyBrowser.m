//
//  _SLRemoteObjectProxyBrowser.m
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

#import "_SLRemoteObjectProxyBrowser.h"
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>



@interface _SLRemoteObjectProxyBrowser () <NSNetServiceBrowserDelegate, NSNetServiceDelegate> {
    NSNetServiceBrowser *_netServiceBrowser;
    NSMutableArray *_resolvedNetServices;
    NSMutableArray *_discoveringNetServices;
}

+ (NSDictionary *)userInfoFromTXTRecordData:(NSData *)txtData;
@property (nonatomic, copy) NSDictionary *userInfo;

@end



@implementation _SLRemoteObjectProxyBrowser

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

#pragma mark - Initialization

- (id)initWithServiceType:(NSString *)serviceType
{
    if (self = [super init]) {
        _serviceType = serviceType;
        
        _resolvedNetServices = [NSMutableArray array];
        _discoveringNetServices = [NSMutableArray array];
        
        _netServiceBrowser = [[NSNetServiceBrowser alloc] init];
        _netServiceBrowser.delegate = self;
        [_netServiceBrowser scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationDidEnterBackgroundCallback:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationWillEnterForegroundCallback:) name:UIApplicationWillEnterForegroundNotification object:nil];
    }
    return self;
}

#pragma mark - Instance methods

- (void)startDiscoveringRemoteObjectHosts
{
    _isDiscoveringRemoteObjectHosts = YES;
    [_netServiceBrowser searchForServicesOfType:_serviceType inDomain:@""];
}

- (void)stopDiscoveringRemoteObjectHosts
{
    _isDiscoveringRemoteObjectHosts = NO;
    [_netServiceBrowser stop];
}

#pragma mark - NSNotificationCenter

- (void)_applicationWillEnterForegroundCallback:(NSNotification *)notification
{
    if (_isDiscoveringRemoteObjectHosts) {
        [_netServiceBrowser searchForServicesOfType:_serviceType inDomain:@""];
    }
}

- (void)_applicationDidEnterBackgroundCallback:(NSNotification *)notification
{
    [_netServiceBrowser stop];
    [_discoveringNetServices removeAllObjects];
    [_resolvedNetServices removeAllObjects];
}

#pragma mark - Memory management

- (void)dealloc
{
    [self stopDiscoveringRemoteObjectHosts];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - NSNetServiceDelegate

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
    [_discoveringNetServices removeObject:sender];
    if (![_resolvedNetServices containsObject:sender]) {
        [_resolvedNetServices addObject:sender];
    }
    
    [_delegate remoteObjectHostBrowserDidChangeNumberOfResolvedNetServices:self];
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
    [_discoveringNetServices removeObject:sender];
    [_resolvedNetServices removeObject:sender];
}

- (void)netService:(NSNetService *)sender didUpdateTXTRecordData:(NSData *)data
{
    self.userInfo = [_SLRemoteObjectProxyBrowser userInfoFromTXTRecordData:data];
}

#pragma mark - NSNetServiceBrowserDelegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)netService moreComing:(BOOL)moreComing
{
    [netService startMonitoring];
    
    if (netService.hostName && netService.port >= 0) {
        self.userInfo = [_SLRemoteObjectProxyBrowser userInfoFromTXTRecordData:netService.TXTRecordData];
        
        [_resolvedNetServices addObject:netService];
        [_delegate remoteObjectHostBrowserDidChangeNumberOfResolvedNetServices:self];
    } else {
        [_discoveringNetServices addObject:netService];
        netService.delegate = self;
        [netService scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        [netService resolveWithTimeout:10.0];

        self.userInfo = [_SLRemoteObjectProxyBrowser userInfoFromTXTRecordData:netService.TXTRecordData];
    }
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didRemoveService:(NSNetService *)netService moreComing:(BOOL)moreComing
{
    [_discoveringNetServices removeObject:netService];
    [_resolvedNetServices removeObject:netService];
    [_delegate remoteObjectHostBrowserDidChangeNumberOfResolvedNetServices:self];
}

#pragma mark - Private category implementation ()

@end
