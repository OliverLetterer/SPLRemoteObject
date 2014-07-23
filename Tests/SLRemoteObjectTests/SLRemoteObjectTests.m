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
#import <CTOpenSSLWrapper.h>
#import "SPLRemoteObjectProxy.h"
#import "SPLRemoteObject.h"
#define EXP_SHORTHAND YES
#import "Expecta.h"
#import "OCMock.h"

@protocol SampleProtocol <NSObject>

- (void)performActionWithCompletionHandler:(void(^)(NSError *error))completionHandler;
- (void)performAction:(NSString *)action withCompletionHandler:(void(^)(NSError *error))completionHandler;

- (void)sayHelloWithResultsCompletionHandler:(void(^)(NSString *response, NSError *error))completionHandler;
- (void)sayHelloForAction:(NSString *)action withResultsCompletionHandler:(void(^)(NSString *response, NSError *error))completionHandler;

@end



@interface SPLRemoteObjectProxyTestTarget : NSObject<SampleProtocol>
@property (nonatomic, copy) NSString *action;
@end

@implementation SPLRemoteObjectProxyTestTarget

- (void)sayHelloWithResultsCompletionHandler:(void (^)(NSString *, NSError *))completionHandler
{
    completionHandler(@"hey there sexy.", nil);
}

- (void)sayHelloForAction:(NSString *)action withResultsCompletionHandler:(void(^)(NSString *response, NSError *error))completionHandler
{
    self.action = action;
    completionHandler(@"hey there sexy.", nil);
}

- (void)performActionWithCompletionHandler:(void(^)(NSError *error))completionHandler
{
    completionHandler(nil);
}

- (void)performAction:(NSString *)action withCompletionHandler:(void (^)(NSError *))completionHandler
{
    self.action = action;
    completionHandler(nil);
}

@end

@interface SPLRemoteObjectTestEncryptionPolicy : NSObject<SPLRemoteObjectEncryptionPolicy>

@property (nonatomic, strong) NSString *key;

@end

@implementation SPLRemoteObjectTestEncryptionPolicy

- (NSData *)dataByEncryptingData:(NSData *)data
{
    NSData *newData = nil;
    BOOL success = CTOpenSSLSymmetricEncrypt(CTOpenSSLCipherAES256, [self.key dataUsingEncoding:NSUTF8StringEncoding], data, &newData);
    NSParameterAssert(success);

    return newData;
}

- (NSData *)dataByDescryptingData:(NSData *)data
{
    NSData *newData = nil;
    BOOL success = CTOpenSSLSymmetricDecrypt(CTOpenSSLCipherAES256, [self.key dataUsingEncoding:NSUTF8StringEncoding], data, &newData);
    NSParameterAssert(success);

    return newData;
}

@end



@interface SPLRemoteObjectTest : XCTestCase

@property (nonatomic, strong) SPLRemoteObjectProxyTestTarget *target;
@property (nonatomic, strong) SPLRemoteObjectProxy *proxy;
@property (nonatomic, strong) SPLRemoteObject<SampleProtocol> *remoteObject;

@end



@implementation SPLRemoteObjectTest

- (void)setUp
{
    [super setUp];

    static NSInteger testCounter = 0;
    testCounter++;

    NSString *serviceName = [NSString stringWithFormat:@"testService%ld", (long)testCounter];

    [Expecta setAsynchronousTestTimeout:10.0];
    
    self.target = [SPLRemoteObjectProxyTestTarget new];
    self.proxy = [[SPLRemoteObjectProxy alloc] initWithServiceName:serviceName target:_target protocol:@protocol(SampleProtocol) completionHandler:^(NSError *error) {
        
    }];
    self.remoteObject = (id)[[SPLRemoteObject alloc] initWithServiceName:serviceName protocol:@protocol(SampleProtocol)];
}

- (void)tearDown
{
    [super tearDown];
    
    self.target = nil;
    self.proxy = nil;
    self.remoteObject = nil;
}

- (void)testInvocationWithResult
{
    __block NSString *response = nil;

    [_remoteObject sayHelloWithResultsCompletionHandler:^(NSString *responseeeee, NSError *error) {
        response = responseeeee;
    }];

    expect(response).will.equal(@"hey there sexy.");
}

- (void)testInvocationWithResultAndEncryption
{
    SPLRemoteObjectTestEncryptionPolicy *policy = [[SPLRemoteObjectTestEncryptionPolicy alloc] init];
    policy.key = @"Hallo";

    self.remoteObject.encryptionPolicy = policy;
    self.proxy.encryptionPolicy = policy;

    __block NSString *response = nil;

    [_remoteObject sayHelloWithResultsCompletionHandler:^(NSString *responseeeee, NSError *error) {
        response = responseeeee;
    }];

    expect(response).will.equal(@"hey there sexy.");
}

- (void)testInvocationWithResultAndArguments
{
    __block NSString *response = nil;

    [_remoteObject sayHelloForAction:@"action" withResultsCompletionHandler:^(NSString *responseeeee, NSError *error) {
        response = responseeeee;
    }];

    expect(response).will.equal(@"hey there sexy.");
    expect(self.target.action).to.equal(@"action");
}

- (void)testInvocationWithoutResult
{
    __block BOOL called = NO;

    [_remoteObject performActionWithCompletionHandler:^(NSError *error) {
        called = YES;
    }];

    expect(called).will.beTruthy();
}

- (void)testInvocationWithoutResultButArguments
{
    __block BOOL called = NO;

    [_remoteObject performAction:@"action" withCompletionHandler:^(NSError *error) {
        called = YES;
    }];

    expect(called).will.beTruthy();
    expect(self.target.action).to.equal(@"action");
}

@end
