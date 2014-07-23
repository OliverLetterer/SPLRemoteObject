//
//  NSData+CTOpenSSL.m
//  CTOpenSSLWrapper
//
//  Created by Oliver Letterer on 04.06.12.
//  Copyright (c) 2012 Home. All rights reserved.
//

#import "NSData+CTOpenSSL.h"
#import <openssl/evp.h>
#import <openssl/rand.h>
#import <openssl/rsa.h>
#import <openssl/engine.h>
#import <openssl/sha.h>
#import <openssl/pem.h>
#import <openssl/bio.h>
#import <openssl/err.h>
#import <openssl/ssl.h>
#import <openssl/md5.h>

@implementation NSData (CTOpenSSL)

- (NSString *)base64EncodedString
{
    return [self base64EncodedStringWithNewLines:NO];
}

- (NSString *)base64EncodedStringWithNewLines:(BOOL)useNewLines
{
    BIO *bio = BIO_new(BIO_s_mem());
    
    BIO *base64Bio = BIO_new(BIO_f_base64());
    if (!useNewLines) {
        BIO_set_flags(base64Bio, BIO_FLAGS_BASE64_NO_NL);
    }
    bio = BIO_push(base64Bio, bio);
    
    NSUInteger length = self.length;
    NSUInteger count = 0;
    
    void *buffer = (void *)self.bytes;
    int bufferSize = (int)MIN(length, (NSUInteger)INT_MAX);
    
    BOOL error = NO;
    
    // Encode all the data
    while (!error && count < length) {
        int result = BIO_write(bio, buffer, bufferSize);
        
        if (result <= 0) {
            error = YES;
        } else {
            count += result;
            buffer = (void *)self.bytes + count;
            bufferSize = (int)MIN((length - count), (NSUInteger)INT_MAX);
        }
    }
    
    if (!BIO_flush(bio)) {
        [NSException raise:NSInternalInconsistencyException format:@"BIO_flush() failed"];
        return nil;
    }
    
    // Create a new string from the data in the memory buffer
    char *base64Pointer = NULL;
    long base64Length = BIO_get_mem_data(bio, &base64Pointer);
	
	// The base64pointer is NOT null terminated.
	NSData *base64data = [NSData dataWithBytesNoCopy:base64Pointer length:base64Length freeWhenDone:NO];
	NSString *base64String = [[NSString alloc] initWithData:base64data encoding:NSUTF8StringEncoding];
    
	BIO_free_all(bio);
    
	return base64String;
}

- (NSString *)hexadecimalValue
{
    NSMutableString *hexadecimalValue = [NSMutableString string];
    unsigned char *bytes = (unsigned char *)self.bytes;
    char temp[3];
    
    for (int i = 0; i < self.length; i++) {
        temp[0] = temp[1] = temp[2] = 0;
        sprintf(temp, "%02x", bytes[i]);
        [hexadecimalValue appendString:[NSString stringWithUTF8String:temp]];
    }
    
    return hexadecimalValue;
}

@end
