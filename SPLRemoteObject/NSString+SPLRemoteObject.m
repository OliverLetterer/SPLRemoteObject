//
//  NSString+SPLRemoteObject.m
//  Pods
//
//  Created by Oliver Letterer on 23.07.14.
//  Copyright (c) 2014 __MyCompanyName__. All rights reserved.
//

#import "NSString+SPLRemoteObject.h"
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>



static NSString *MD5(NSString *string)
{
    unsigned char md5Buffer[CC_MD5_DIGEST_LENGTH];
    CC_MD5(string.UTF8String, (CC_LONG)strlen(string.UTF8String), md5Buffer);

    NSMutableString *result = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [result appendFormat:@"%02x",md5Buffer[i]];
    }

    return result;
}



@implementation NSString (SPLRemoteObject)

- (NSString *)netServiceTypeWithProtocol:(Protocol *)protocol
{
    NSString *type = [NSString stringWithFormat:@"%@%s", self, protocol_getName(protocol)];
    return [NSString stringWithFormat:@"_%@._tcp.", MD5(type)];
}

@end
