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

@import CFNetwork;

static NSDictionary *CFStreamErrorGetDictionary(CFStreamError error)
{
    return @{
             NSNetServicesErrorDomain: @(error.domain),
             NSNetServicesErrorCode: @(error.error),
             };
}



@interface SPLNetService ()

@property (nonatomic, assign) BOOL isPublishing;
@property (nonatomic, assign) BOOL isResolving;

@property (nonatomic, assign) CFNetServiceMonitorRef netServiceMonitor;

- (void)_txtRecordDataDidChange;
- (void)_netServiceCallbackWithError:(CFStreamError *)error;

@end

static void _SPLNetServiceClientCallback(CFNetServiceRef theService, CFStreamError *error, void *info)
{
    SPLNetService *self = (__bridge id)info;
    [self _netServiceCallbackWithError:error];
}

static void _SPLNetServiceNetServiceMonitorCallback(CFNetServiceMonitorRef theMonitor, CFNetServiceRef theService, CFNetServiceMonitorType typeInfo, CFDataRef rdata, CFStreamError *error, void *info)
{
    SPLNetService *self = (__bridge id)info;
    [self _txtRecordDataDidChange];
}



@implementation SPLNetService

#pragma mark - setters and getters

- (NSData *)TXTRecordData
{
    return (__bridge NSData *)CFNetServiceGetTXTData(self.netService);
}

- (void)setTXTRecordData:(NSData *)TXTRecordData
{
    CFNetServiceSetTXTData(self.netService, (__bridge CFDataRef)TXTRecordData);
}

- (void)setNetService:(CFNetServiceRef)netService
{
    if (netService != _netService) {
        if (_netService != NULL) {
            CFRelease(_netService), _netService = NULL;
        }

        if (netService) {
            _netService = (CFNetServiceRef)CFRetain(netService);
        }
    }
}

- (void)setNetServiceMonitor:(CFNetServiceMonitorRef)netServiceMonitor
{
    if (netServiceMonitor != _netServiceMonitor) {
        if (_netServiceMonitor != NULL) {
            CFRelease(_netServiceMonitor), _netServiceMonitor = NULL;
        }

        if (netServiceMonitor) {
            _netServiceMonitor = (CFNetServiceMonitorRef)CFRetain(netServiceMonitor);
        }
    }
}

- (NSString *)domain
{
    return (__bridge NSString *)CFNetServiceGetDomain(self.netService);
}

- (NSString *)type
{
    return (__bridge NSString *)CFNetServiceGetType(self.netService);
}

- (NSString *)name
{
    return (__bridge NSString *)CFNetServiceGetName(self.netService);
}

- (NSInteger)port
{
    return (NSInteger)CFNetServiceGetPortNumber(self.netService);
}

- (NSString *)hostName
{
    return (__bridge NSString *)CFNetServiceGetTargetHost(self.netService);
}

- (NSArray *)addresses
{
    return (__bridge NSArray *)CFNetServiceGetAddressing(self.netService);
}

#pragma mark - Initialization

- (instancetype)initWithCFNetService:(CFNetServiceRef)netService
{
    if (self = [super init]) {
        _netService = (CFNetServiceRef)CFRetain(netService);
        CFNetServiceClientContext netServiceContext = { .info = (__bridge void *)self };
        CFNetServiceSetClient(_netService, &_SPLNetServiceClientCallback, &netServiceContext);

        CFNetServiceClientContext context = { .info = (__bridge void *)self };
        _netServiceMonitor = CFNetServiceMonitorCreate(kCFAllocatorDefault, self.netService, &_SPLNetServiceNetServiceMonitorCallback, &context);

        [self scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    }
    return self;
}

- (instancetype)initWithDomain:(NSString *)domain type:(NSString *)type name:(NSString *)name port:(NSInteger)port
{
    if (self = [super init]) {
        _netService = CFNetServiceCreate(kCFAllocatorDefault, (__bridge CFStringRef)domain, (__bridge CFStringRef)type, (__bridge CFStringRef)name, (SInt32)port);
        CFNetServiceClientContext netServiceContext = { .info = (__bridge void *)self };
        CFNetServiceSetClient(_netService, &_SPLNetServiceClientCallback, &netServiceContext);

        [self scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    }
    return self;
}

- (instancetype)initWithDomain:(NSString *)domain type:(NSString *)type name:(NSString *)name
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (void)dealloc
{
    [self removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];

    if (self.netServiceMonitor) {
        CFStreamError error;
        CFNetServiceMonitorStop(self.netServiceMonitor, &error);
    }

    CFNetServiceCancel(self.netService);
    CFNetServiceClientContext netServiceContext;
    CFNetServiceSetClient(self.netService, NULL, &netServiceContext);

    self.netService = NULL;
    self.netServiceMonitor = NULL;
}

- (BOOL)isEqual:(id)object
{
    if ([object isKindOfClass:[SPLNetService class]]) {
        SPLNetService *otherNetService = object;
        return CFEqual(self.netService, otherNetService.netService);
    }

    return [super isEqual:object];
}

#pragma mark - Instance methods

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
    CFNetServiceScheduleWithRunLoop(self.netService, aRunLoop.getCFRunLoop, (__bridge CFStringRef)mode);

    if (self.netServiceMonitor) {
        CFNetServiceMonitorScheduleWithRunLoop(self.netServiceMonitor, aRunLoop.getCFRunLoop, (__bridge CFStringRef)mode);
    }
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
    CFNetServiceUnscheduleFromRunLoop(self.netService, aRunLoop.getCFRunLoop, (__bridge CFStringRef)mode);

    if (self.netServiceMonitor) {
        CFNetServiceMonitorUnscheduleFromRunLoop(self.netServiceMonitor, aRunLoop.getCFRunLoop, (__bridge CFStringRef)mode);
    }
}

- (void)publish
{
    if ([self.delegate respondsToSelector:@selector(netServiceWillPublish:)]) {
        [self.delegate netServiceWillPublish:self];
    }

    self.isPublishing = YES;
    CFStreamError error;
    Boolean success = CFNetServiceRegisterWithOptions(self.netService, kCFNetServiceFlagNoAutoRename, &error);

    if (!success) {
        if ([self.delegate respondsToSelector:@selector(netService:didNotPublish:)]) {
            [self.delegate netService:self didNotPublish:CFStreamErrorGetDictionary(error)];
        }
    }
}

- (void)stop
{
    CFNetServiceCancel(self.netService);

    if ([self.delegate respondsToSelector:@selector(netServiceDidStop:)]) {
        [self.delegate netServiceDidStop:self];
    }
}

- (void)startMonitoring
{
    CFStreamError error;
    CFNetServiceMonitorStart(self.netServiceMonitor, kCFNetServiceMonitorTXT, &error);
}

- (void)stopMonitoring
{
    CFStreamError error;
    CFNetServiceMonitorStop(self.netServiceMonitor, &error);
}

- (void)resolveWithTimeout:(NSTimeInterval)timeout
{
    if ([self.delegate respondsToSelector:@selector(netServiceWillResolve:)]) {
        [self.delegate netServiceWillResolve:self];
    }

    self.isResolving = YES;
    CFStreamError error;
    Boolean success = CFNetServiceResolveWithTimeout(self.netService, timeout, &error);

    if (!success) {
        if ([self.delegate respondsToSelector:@selector(netService:didNotResolve:)]) {
            [self.delegate netService:self didNotResolve:CFStreamErrorGetDictionary(error)];
        }
    }
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ %@ %@ %@ (%@:%ld)", super.description, self.domain, self.type, self.name, self.hostName, (long)self.port];
}

#pragma mark - CFNetService callbacks

- (void)_txtRecordDataDidChange
{
    if ([self.delegate respondsToSelector:@selector(netService:didUpdateTXTRecordData:)]) {
        [self.delegate netService:self didUpdateTXTRecordData:self.TXTRecordData];
    }
}

- (void)_netServiceCallbackWithError:(CFStreamError *)error
{
    if (self.isPublishing) {
        if (error->domain == 0) {
            if ([self.delegate respondsToSelector:@selector(netServiceDidPublish:)]) {
                [self.delegate netServiceDidPublish:self];
            }
        } else {
            if ([self.delegate respondsToSelector:@selector(netService:didNotPublish:)]) {
                [self.delegate netService:self didNotPublish:CFStreamErrorGetDictionary(*error)];
            }
        }

        self.isPublishing = NO;
    }

    if (self.isResolving) {
        if (error->domain == 0) {
            if ([self.delegate respondsToSelector:@selector(netServiceDidResolveAddress:)]) {
                [self.delegate netServiceDidResolveAddress:self];
            }
        } else {
            if ([self.delegate respondsToSelector:@selector(netService:didNotResolve:)]) {
                [self.delegate netService:self didNotResolve:CFStreamErrorGetDictionary(*error)];
            }
        }

        self.isResolving = NO;
    }
}

@end
