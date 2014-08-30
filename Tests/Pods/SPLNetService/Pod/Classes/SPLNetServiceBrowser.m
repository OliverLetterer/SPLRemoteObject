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

@import CFNetwork;

#import "SPLNetServiceBrowser.h"

static NSDictionary *CFStreamErrorGetDictionary(CFStreamError error)
{
    return @{
             NSNetServicesErrorDomain: @(error.domain),
             NSNetServicesErrorCode: @(error.error),
             };
}



@interface SPLNetServiceBrowser ()

@property (nonatomic, readonly) BOOL isSearching;
@property (nonatomic, assign) BOOL isSearchingForNetServices;
@property (nonatomic, assign) BOOL isSearchingForDomains;

@property (nonatomic, assign) CFNetServiceBrowserRef browser;
@property (nonatomic, strong) NSMutableArray *discoveredNetServices;

- (void)_didFindDomain:(NSString *)domain moreComing:(BOOL)moreComing;
- (void)_didRemoveDomain:(NSString *)domain moreComing:(BOOL)moreComing;

- (void)_didFindNetService:(CFNetServiceRef)netService moreComing:(BOOL)moreComing;
- (void)_didRemoveNetService:(CFNetServiceRef)netService moreComing:(BOOL)moreComing;

@end



static void _SPLNetServiceBrowserBrowserCallback(CFNetServiceBrowserRef browser, CFOptionFlags flags, CFTypeRef domainOrService, CFStreamError *error, void *info)
{
    BOOL moreComing = (flags & kCFNetServiceFlagMoreComing) != 0;
    BOOL shoudRemove = flags & kCFNetServiceFlagRemove;
    BOOL isNormalDomain = flags & kCFNetServiceFlagIsDomain;
    BOOL isNetService = !isNormalDomain;

    SPLNetServiceBrowser *self = (__bridge id)info;

    if (error && error->error != 0) {
        if (self.isSearching && [self.delegate respondsToSelector:@selector(netServiceBrowser:didNotSearch:)]) {
            [self.delegate netServiceBrowser:self didNotSearch:CFStreamErrorGetDictionary(*error)];
        }
        return;
    }

    if (isNormalDomain) {
        if (self.isSearchingForDomains) {
            if (shoudRemove) {
                [self _didRemoveDomain:(__bridge id)domainOrService moreComing:moreComing];
            } else {
                [self _didFindDomain:(__bridge id)domainOrService moreComing:moreComing];
            }
        }
    } else if (isNetService) {
        if (self.isSearchingForNetServices) {
            CFNetServiceRef netService = (CFNetServiceRef)domainOrService;
            if (shoudRemove) {
                [self _didRemoveNetService:netService moreComing:moreComing];
            } else {
                [self _didFindNetService:netService moreComing:moreComing];
            }
        }
    } else {
        NSCParameterAssert(NO);
    }
}



@implementation SPLNetServiceBrowser

#pragma mark - setters and getters

- (BOOL)isSearching
{
    return self.isSearchingForNetServices || self.isSearchingForDomains;
}

- (void)setBrowser:(CFNetServiceBrowserRef)browser
{
    if (browser != _browser) {
        if (_browser != NULL) {
            CFRelease(_browser), _browser = NULL;
        }

        if (browser) {
            _browser = (CFNetServiceBrowserRef)CFRetain(browser);
        }
    }
}

#pragma mark - Initialization

- (instancetype)init
{
    if (self = [super init]) {
        CFNetServiceClientContext context = { .info = (__bridge void *)self };
        _browser = CFNetServiceBrowserCreate(kCFAllocatorDefault, &_SPLNetServiceBrowserBrowserCallback, &context);
        _discoveredNetServices = [NSMutableArray array];

        [self scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    }
    return self;
}

- (void)dealloc
{
    CFNetServiceBrowserInvalidate(self.browser);
    self.browser = NULL;
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
    CFNetServiceBrowserScheduleWithRunLoop(self.browser, aRunLoop.getCFRunLoop, (__bridge CFStringRef)mode);
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
    CFNetServiceBrowserUnscheduleFromRunLoop(self.browser, aRunLoop.getCFRunLoop, (__bridge CFStringRef)mode);
}

- (void)stop
{
    CFStreamError error;
    CFNetServiceBrowserStopSearch(self.browser, &error);

    self.isSearchingForNetServices = NO;
    self.isSearchingForDomains = NO;

    if (error.domain == 0 && [self.delegate respondsToSelector:@selector(netServiceBrowserDidStopSearch:)]) {
        [self.delegate netServiceBrowserDidStopSearch:self];
    }
}

- (void)searchForBrowsableDomains
{
    if ([self.delegate respondsToSelector:@selector(netServiceBrowserWillSearch:)]) {
        [self.delegate netServiceBrowserWillSearch:self];
    }

    CFStreamError error;
    Boolean success = CFNetServiceBrowserSearchForDomains(self.browser, false, &error);

    if (!success) {
        if ([self.delegate respondsToSelector:@selector(netServiceBrowser:didNotSearch:)]) {
            [self.delegate netServiceBrowser:self didNotSearch:CFStreamErrorGetDictionary(error)];
        }
    } else {
        self.isSearchingForDomains = YES;
    }
}

- (void)searchForRegistrationDomains
{
    if ([self.delegate respondsToSelector:@selector(netServiceBrowserWillSearch:)]) {
        [self.delegate netServiceBrowserWillSearch:self];
    }

    CFStreamError error;
    Boolean success = CFNetServiceBrowserSearchForDomains(self.browser, true, &error);

    if (!success) {
        if ([self.delegate respondsToSelector:@selector(netServiceBrowser:didNotSearch:)]) {
            [self.delegate netServiceBrowser:self didNotSearch:CFStreamErrorGetDictionary(error)];
        }
    } else {
        self.isSearchingForDomains = YES;
    }
}

- (void)searchForServicesOfType:(NSString *)type inDomain:(NSString *)domainString
{
    if ([self.delegate respondsToSelector:@selector(netServiceBrowserWillSearch:)]) {
        [self.delegate netServiceBrowserWillSearch:self];
    }

    CFStreamError error;
    Boolean success = CFNetServiceBrowserSearchForServices(self.browser, (__bridge CFStringRef)domainString, (__bridge CFStringRef)type, &error);

    if (!success) {
        if ([self.delegate respondsToSelector:@selector(netServiceBrowser:didNotSearch:)]) {
            [self.delegate netServiceBrowser:self didNotSearch:CFStreamErrorGetDictionary(error)];
        }
    } else {
        self.isSearchingForNetServices = YES;
    }
}

#pragma mark - Private category implementation ()

- (void)_didFindDomain:(NSString *)domain moreComing:(BOOL)moreComing
{
    if ([self.delegate respondsToSelector:@selector(netServiceBrowser:didFindDomain:moreComing:)]) {
        [self.delegate netServiceBrowser:self didFindDomain:domain moreComing:moreComing];
    }
}

- (void)_didRemoveDomain:(NSString *)domain moreComing:(BOOL)moreComing
{
    if ([self.delegate respondsToSelector:@selector(netServiceBrowser:didRemoveDomain:moreComing:)]) {
        [self.delegate netServiceBrowser:self didRemoveDomain:domain moreComing:moreComing];
    }
}

- (void)_didFindNetService:(CFNetServiceRef)netServiceRef moreComing:(BOOL)moreComing
{
    SPLNetService *netService = [[SPLNetService alloc] initWithCFNetService:netServiceRef];

    NSInteger existingIndex = [self.discoveredNetServices indexOfObject:netService];
    if (existingIndex != NSNotFound) {
        if ([self.delegate respondsToSelector:@selector(netServiceBrowser:didRemoveService:moreComing:)]) {
            SPLNetService *existingService = self.discoveredNetServices[existingIndex];
            [self.delegate netServiceBrowser:self didRemoveService:existingService moreComing:moreComing];
        }

        [self.discoveredNetServices replaceObjectAtIndex:existingIndex withObject:netService];
        if ([self.delegate respondsToSelector:@selector(netServiceBrowser:didFindService:moreComing:)]) {
            [self.delegate netServiceBrowser:self didFindService:netService moreComing:moreComing];
        }
    } else {
        [self.discoveredNetServices addObject:netService];
        if ([self.delegate respondsToSelector:@selector(netServiceBrowser:didFindService:moreComing:)]) {
            [self.delegate netServiceBrowser:self didFindService:netService moreComing:moreComing];
        }
    }
}

- (void)_didRemoveNetService:(CFNetServiceRef)netServiceRef moreComing:(BOOL)moreComing
{
    SPLNetService *netServiceToRemove = nil;

    for (SPLNetService *netService in self.discoveredNetServices) {
        if (CFEqual(netService.netService, netServiceRef)) {
            netServiceToRemove = netService;
            break;
        }
    }

    NSParameterAssert(netServiceToRemove != nil);
    [self.discoveredNetServices removeObject:netServiceToRemove];
    if ([self.delegate respondsToSelector:@selector(netServiceBrowser:didRemoveService:moreComing:)]) {
        [self.delegate netServiceBrowser:self didRemoveService:netServiceToRemove moreComing:moreComing];
    }
}

@end
