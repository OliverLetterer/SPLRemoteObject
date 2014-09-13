//
//  _SPLRemoteObjectProxyBrowser.m
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

#import "_SPLRemoteObjectProxyBrowser.h"
#import "SPLRemoteObject.h"
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>



@interface _SPLRemoteObjectProxyBrowser () <NSNetServiceBrowserDelegate, NSNetServiceDelegate>

@property (nonatomic, strong) NSNetService *resolvedNetService;
@property (nonatomic, strong) NSNetService *discoveringNetService;
@property (nonatomic, strong) NSNetServiceBrowser *netServiceBrowser;

@property (nonatomic, copy) NSDictionary *userInfo;

@end



@implementation _SPLRemoteObjectProxyBrowser

#pragma mark - Initialization

- (instancetype)initWithName:(NSString *)name netServiceType:(NSString *)netServiceType
{
    if (self = [super init]) {
        _name = name;
        _netServiceType = netServiceType;

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
    [_netServiceBrowser searchForServicesOfType:self.netServiceType inDomain:@""];
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
        [_netServiceBrowser searchForServicesOfType:self.netServiceType inDomain:@""];
    }
}

- (void)_applicationDidEnterBackgroundCallback:(NSNotification *)notification
{
    [_netServiceBrowser stop];
    self.discoveringNetService = nil;
    self.resolvedNetService = nil;
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
    if (sender == self.discoveringNetService) {
        self.discoveringNetService = nil;
        self.resolvedNetService = sender;
    }
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
    self.discoveringNetService = nil;
    self.resolvedNetService = nil;
}

- (void)netService:(NSNetService *)sender didUpdateTXTRecordData:(NSData *)data
{
    self.userInfo = [SPLRemoteObject userInfoFromTXTRecordData:data];
}

#pragma mark - NSNetServiceBrowserDelegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)netService moreComing:(BOOL)moreComing
{
    if (![netService.name isEqual:self.name]) {
        return;
    }

    if (netService.hostName && netService.port >= 0) {
        self.resolvedNetService = netService;
    } else {
        self.discoveringNetService = netService;
        netService.delegate = self;
        [netService scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        [netService resolveWithTimeout:60.0];
    }

    self.userInfo = [SPLRemoteObject userInfoFromTXTRecordData:netService.TXTRecordData];
    [netService startMonitoring];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didRemoveService:(NSNetService *)netService moreComing:(BOOL)moreComing
{
    if (![netService.name isEqual:self.name]) {
        return;
    }

    self.discoveringNetService = nil;
    self.resolvedNetService = nil;
}

#pragma mark - Private category implementation ()

@end
