//
//  CTOpenSSLWrapper.m
//  CTOpenSSLWrapper
//
//  Created by Oliver Letterer on 27.11.11.
//  Copyright (c) 2011 Home. All rights reserved.
//

#import "CTOpenSSLWrapper.h"
#import <dispatch/dispatch.h>
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

#pragma mark - Initialization

void CTOpenSSLInitialize(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        OpenSSL_add_all_algorithms();
        ERR_load_crypto_strings();
    });
}
