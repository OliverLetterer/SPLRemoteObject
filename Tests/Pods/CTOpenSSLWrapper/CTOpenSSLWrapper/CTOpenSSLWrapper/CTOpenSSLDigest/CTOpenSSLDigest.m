//
//  CTOpenSSLDigest.m
//  CTOpenSSLWrapper
//
//  Created by Oliver Letterer on 05.06.12.
//  Copyright 2012 Home. All rights reserved.
//

#import "CTOpenSSLDigest.h"
#import "CTOpenSSLWrapper.h"
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

NSString *NSStringFromCTOpenSSLDigestType(CTOpenSSLDigestType digestType)
{
    switch (digestType) {
        case CTOpenSSLDigestTypeMD5:
            return @"MD5";
            break;
        case CTOpenSSLDigestTypeSHA1:
            return @"SHA1";
            break;
        case CTOpenSSLDigestTypeSHA256:
            return @"SHA256";
            break;
        case CTOpenSSLDigestTypeSHA512:
            return @"SHA512";
            break;
        default:
            [NSException raise:NSInternalInconsistencyException format:@"digestType not supported %d", digestType];
            break;
    }

    return nil;
}

int CTOpenSSLRSASignTypeFromDigestType(CTOpenSSLDigestType digestType)
{
    switch (digestType) {
        case CTOpenSSLDigestTypeMD5:
            return NID_md5;
            break;
        case CTOpenSSLDigestTypeSHA1:
            return NID_sha1;
            break;
        case CTOpenSSLDigestTypeSHA256:
            return NID_sha256;
            break;
        case CTOpenSSLDigestTypeSHA512:
            return NID_sha512;
            break;
        default:
            [NSException raise:NSInternalInconsistencyException format:@"digestType not supported %d", digestType];
            break;
    }

    return -1;
}

NSData *CTOpenSSLGenerateDigestFromData(NSData *data, CTOpenSSLDigestType digestType)
{
    CTOpenSSLInitialize();

    unsigned char outputBuffer[EVP_MAX_MD_SIZE];
    unsigned int outputLength;
    unsigned long inputLength = data.length;
    unsigned char *inputBytes = (unsigned char *)data.bytes;
    EVP_MD_CTX context;

    NSString *digestName = NSStringFromCTOpenSSLDigestType(digestType);
    const EVP_MD *digest = EVP_get_digestbyname(digestName.UTF8String);

    if (!digest) {
        [NSException raise:NSInternalInconsistencyException format:@"digest of type (%d %@) not found", digestType, digestName];
    }

    EVP_MD_CTX_init(&context);
    EVP_DigestInit(&context, digest);

    if(!EVP_DigestUpdate(&context,inputBytes,inputLength)) {
        [NSException raise:NSInternalInconsistencyException format:@"EVP_DigestUpdate() failed"];
    }

    if (!EVP_DigestFinal(&context, outputBuffer, &outputLength)) {
        [NSException raise:NSInternalInconsistencyException format:@"EVP_DigestFinal() failed"];
    }

    EVP_MD_CTX_cleanup(&context);

    return [NSData dataWithBytes:outputBuffer length:outputLength];
}
