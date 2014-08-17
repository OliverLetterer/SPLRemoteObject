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

@import Foundation;

@class SPLNetService;



@protocol SPLNetServiceDelegate <NSObject>

@optional
- (void)netServiceWillPublish:(SPLNetService *)sender;
- (void)netServiceDidPublish:(SPLNetService *)sender;
- (void)netService:(SPLNetService *)sender didNotPublish:(NSDictionary *)errorDict;


- (void)netServiceWillResolve:(SPLNetService *)sender;
- (void)netServiceDidResolveAddress:(SPLNetService *)sender;
- (void)netService:(SPLNetService *)sender didNotResolve:(NSDictionary *)errorDict;

- (void)netServiceDidStop:(SPLNetService *)sender;
- (void)netService:(SPLNetService *)sender didUpdateTXTRecordData:(NSData *)data;

@end



/**
 @abstract  <#abstract comment#>
 */
@interface SPLNetService : NSObject

@property (nonatomic, assign) CFNetServiceRef netService; // retained
- (instancetype)initWithCFNetService:(CFNetServiceRef)netService;

- (instancetype)initWithDomain:(NSString *)domain type:(NSString *)type name:(NSString *)name port:(NSInteger)port;
- (instancetype)initWithDomain:(NSString *)domain type:(NSString *)type name:(NSString *)name UNAVAILABLE_ATTRIBUTE;

@property (nonatomic, weak) id<SPLNetServiceDelegate> delegate;

@property (nonatomic, copy) NSData *TXTRecordData;

@property (readonly, copy) NSString *domain;
@property (readonly, copy) NSString *name;
@property (readonly, copy) NSString *type;
@property (readonly) NSInteger port;
@property (readonly, copy) NSString *hostName;
@property (readonly, copy) NSArray *addresses;

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;

- (void)publish;
- (void)stop;

- (void)startMonitoring;
- (void)stopMonitoring;

- (void)resolveWithTimeout:(NSTimeInterval)timeout;

@end
