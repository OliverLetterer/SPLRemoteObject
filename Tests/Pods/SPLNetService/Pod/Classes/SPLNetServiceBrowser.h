/*
 SPLNetService
 Copyright (c) 2014 Oliver Letterer <oliver.letterer@gmail.com>, Sparrow-Labs

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 */

#import "SPLNetService.h"
@import Foundation;

@class SPLNetServiceBrowser;

@protocol SPLNetServiceBrowserDelegate <NSObject>

@optional
- (void)netServiceBrowserWillSearch:(SPLNetServiceBrowser *)aNetServiceBrowser;
- (void)netServiceBrowserDidStopSearch:(SPLNetServiceBrowser *)aNetServiceBrowser;

- (void)netServiceBrowser:(SPLNetServiceBrowser *)aNetServiceBrowser didNotSearch:(NSDictionary *)errorDict;

- (void)netServiceBrowser:(SPLNetServiceBrowser *)aNetServiceBrowser didFindDomain:(NSString *)domainString moreComing:(BOOL)moreComing;
- (void)netServiceBrowser:(SPLNetServiceBrowser *)aNetServiceBrowser didFindService:(SPLNetService *)aNetService moreComing:(BOOL)moreComing;

- (void)netServiceBrowser:(SPLNetServiceBrowser *)aNetServiceBrowser didRemoveDomain:(NSString *)domainString moreComing:(BOOL)moreComing;
- (void)netServiceBrowser:(SPLNetServiceBrowser *)aNetServiceBrowser didRemoveService:(SPLNetService *)aNetService moreComing:(BOOL)moreComing;


@end



/**
 @abstract  <#abstract comment#>
 */
@interface SPLNetServiceBrowser : NSObject

- (instancetype)init;

@property (assign) id <SPLNetServiceBrowserDelegate> delegate;

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;

- (void)searchForBrowsableDomains;
- (void)searchForRegistrationDomains;
- (void)searchForServicesOfType:(NSString *)type inDomain:(NSString *)domainString;

- (void)stop;

@end
