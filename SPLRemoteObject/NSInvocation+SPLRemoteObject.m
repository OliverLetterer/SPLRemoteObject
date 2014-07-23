//
//  NSInvocation+SPLRemoteObject.m
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

#import "NSInvocation+SPLRemoteObject.h"
#import "_SPLNil.h"
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

    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:methodDescription.types];

    NSMutableString *stringToHash = [NSMutableString stringWithString:NSStringFromSelector(methodDescription.name)];
    [stringToHash appendFormat:@"%c", signature.methodReturnType[0]];

    for (NSInteger i = 0; i < signature.numberOfArguments; i++) {
        [stringToHash appendFormat:@"%c", [signature getArgumentTypeAtIndex:i][0]];
    }

    const char *string = stringToHash.UTF8String;
    unsigned char md5Buffer[CC_MD5_DIGEST_LENGTH];
    CC_MD5(string, (CC_LONG)strlen(string), md5Buffer);

    // Convert MD5 value in the buffer to NSString of hex values
    NSMutableString *hash = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [hash appendFormat:@"%02x", md5Buffer[i]];
    }
    
    return hash;
}



@implementation NSInvocation (SPLRemoteObject)

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
    if (objects.count + 3 != methodSignature.numberOfArguments) {
        NSLog(@"number of arguments does not match => rejecting remote request");
        return nil;
    }

    [objects enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop) {
        if ([object isKindOfClass:[_SPLNil class]]) {
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

    for (NSInteger i = 2; i < self.methodSignature.numberOfArguments - 1; i++) {
        __unsafe_unretained NSObject<NSCoding> *object = nil;
        [self getArgument:&object atIndex:i];

        if (!object) {
            _SPLNil *nilObject = [[_SPLNil alloc] init];
            [objects addObject:nilObject];
        } else {
            NSAssert([object conformsToProtocol:@protocol(NSSecureCoding)], @"all objects must conform to NSSecureCoding");
            [objects addObject:object];
        }
    }

    dictionaryRepresentation[@"objects"] = objects;

    return dictionaryRepresentation;
}

@end
