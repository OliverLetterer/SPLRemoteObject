//
//  NSInvocation+SLRemoteObject.m
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

#import "NSInvocation+SLRemoteObject.h"
#import "_SLNil.h"
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>

static NSString *protocol_getHashForSelector(Protocol *protocol, SEL selector)
{
    NSCParameterAssert(protocol);
    NSCParameterAssert(selector);
    
    struct objc_method_description methodDescription = protocol_getMethodDescription(protocol, selector, YES, YES);
    if (!methodDescription.name || !methodDescription.types) {
        methodDescription = protocol_getMethodDescription(protocol, selector, NO, YES);
    }
    
    if (!methodDescription.name) {
        return nil;
    }
    
    NSString *stringToHash = [NSString stringWithFormat:@"%@%s", NSStringFromSelector(methodDescription.name), methodDescription.types];
    
    const char *string = stringToHash.UTF8String;
    unsigned char md5Buffer[CC_MD5_DIGEST_LENGTH];
    CC_MD5(string, strlen(string), md5Buffer);
    
    // Convert MD5 value in the buffer to NSString of hex values
    NSMutableString *hash = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [hash appendFormat:@"%02x", md5Buffer[i]];
    }
    
    return hash;
}



@implementation NSInvocation (SLRemoteObject)

- (NSInvocation *)asynchronInvocationForProtocol:(Protocol *)protocol
{
    SEL originalSelector = self.selector;
    SEL asynchronSelector = NULL;
    
    if ([NSStringFromSelector(originalSelector) hasSuffix:@":"]) {
        asynchronSelector = NSSelectorFromString([NSString stringWithFormat:@"%@withCompletionHandler:", NSStringFromSelector(originalSelector)]);
    } else {
        asynchronSelector = NSSelectorFromString([NSString stringWithFormat:@"%@WithCompletionHandler:", NSStringFromSelector(originalSelector)]);
    }
    
    struct objc_method_description methodDescription = protocol_getMethodDescription(protocol, asynchronSelector, NO, YES);
    if (!methodDescription.types) {
        return nil;
    }
    
    NSMethodSignature *methodSignature = [NSMethodSignature signatureWithObjCTypes:methodDescription.types];
    
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
    invocation.selector = asynchronSelector;
    
    for (int i = 0; i < self.methodSignature.numberOfArguments; i++) {
        if (i == 1) {
            continue;
        }
        
        void *argument = NULL;
        [self getArgument:&argument atIndex:i];
        [invocation setArgument:&argument atIndex:i];
    }
    
    return invocation;
}

+ (NSInvocation *)invocationWithRemoteObjectDictionaryRepresentation:(NSDictionary *)dictionaryRepresentation forProtocol:(Protocol *)protocol
{
    NSParameterAssert(protocol);
    
    NSString *selectorName = dictionaryRepresentation[@"selector"];
    SEL selector = NSSelectorFromString(selectorName);
    
    
    
    if (!selector) {
        NSLog(@"selector %@ not found", selectorName);
        return nil;
    }
    
    NSString *protocolHash = protocol_getHashForSelector(protocol, selector);
    if (![protocolHash isEqual:dictionaryRepresentation[@"protocol_hash"]]) {
        NSLog(@"protocol hash does not match, => rejecting remote request");
        return nil;
    }
    
    struct objc_method_description methodDescription = protocol_getMethodDescription(protocol, selector, YES, YES);
    if (!methodDescription.types) {
        NSLog(@"protocol %s does not contain %@", protocol_getName(protocol), selectorName);
        return nil;
    }
    
    NSMethodSignature *methodSignature = [NSMethodSignature signatureWithObjCTypes:methodDescription.types];
    
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
    invocation.selector = selector;
    
    NSArray *objects = dictionaryRepresentation[@"objects"];
    if (objects.count + 2 != methodSignature.numberOfArguments) {
        NSLog(@"number of arguments does not match => rejecting remote request");
        return nil;
    }
    
    [objects enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop) {
        if ([object isKindOfClass:[_SLNil class]]) {
            id nilObject = nil;
            [invocation setArgument:&nilObject atIndex:index + 2];
        } else {
            [invocation setArgument:&object atIndex:index + 2];
        }
    }];
    
    return invocation;
}

- (NSDictionary *)remoteObjectDictionaryRepresentationForProtocol:(Protocol *)protocol
{
    NSParameterAssert(protocol);
    
    NSMutableDictionary *dictionaryRepresentation = @{
                                                      @"selector": NSStringFromSelector(self.selector),
                                                      @"protocol_hash": protocol_getHashForSelector(protocol, self.selector)
                                                      }.mutableCopy;
    
    NSMutableArray *objects = [NSMutableArray arrayWithCapacity:self.methodSignature.numberOfArguments];
    
    for (uint i = 2; i < self.methodSignature.numberOfArguments; i++) {
        __unsafe_unretained NSObject<NSCoding> *object = nil;
        [self getArgument:&object atIndex:i];
        
        if (!object) {
            _SLNil *nilObject = [[_SLNil alloc] init];
            [objects addObject:nilObject];
        } else {
            NSAssert([object conformsToProtocol:@protocol(NSCoding)], @"all objects must conform to NSCoding");
            [objects addObject:object];
        }
    }
    
    dictionaryRepresentation[@"objects"] = objects;
    
    return dictionaryRepresentation;
}

@end
