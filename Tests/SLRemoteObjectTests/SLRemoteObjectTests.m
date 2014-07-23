//
//  SPLRemoteObjectTests.m
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

#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#import "SPLRemoteObjectProxy.h"
#import "SPLRemoteObject.h"
#define EXP_SHORTHAND YES
#import "Expecta.h"
#import "OCMock.h"

@protocol SampleProtocol <NSObject>

@required
- (NSString *)sayHello;

@optional
- (void)sayHelloWithCompletionHandler:(void(^)(NSString *response, NSError *error))completionHandler;

@end



@interface SPLRemoteObjectProxyTestTarget : NSObject<SampleProtocol> @end

@implementation SPLRemoteObjectProxyTestTarget

- (NSString *)sayHello
{
    return @"hey there sexy.";
}

@end



@interface SPLRemoteObjectTests : XCTestCase {
    SPLRemoteObjectProxyTestTarget *_target;
    SPLRemoteObjectProxy *_proxy;
    id<SampleProtocol> _remoteObject;
}

@end



@implementation SPLRemoteObjectTests

- (void)setUp
{
    [super setUp];
    
    _target = [SPLRemoteObjectProxyTestTarget new];
    _proxy = [[SPLRemoteObjectProxy alloc] initWithServiceName:@"someServiceName" target:_target protocol:@protocol(SampleProtocol) options:nil completionHandler:^(NSError *error) {
        
    }];
    _remoteObject = [SPLRemoteObject remoteObjectWithServiceName:@"someServiceName" protocol:@protocol(SampleProtocol) options:nil];
}

- (void)tearDown
{
    [super tearDown];
    
    _target = nil;
    _proxy = nil;
    _remoteObject = nil;
}

- (void)testThatSPLRemoteObjectSendMessageToAnSPLRemoteObjectProxyAndReceivesAResponse
{
    [Expecta setAsynchronousTestTimeout:5.0];
    
    __block NSString *response = nil;
    
    [_remoteObject sayHelloWithCompletionHandler:^(NSString *responseeeee, NSError *error) {
        response = responseeeee;
    }];
    
    expect(response).will.equal(@"hey there sexy.");
}

@end
