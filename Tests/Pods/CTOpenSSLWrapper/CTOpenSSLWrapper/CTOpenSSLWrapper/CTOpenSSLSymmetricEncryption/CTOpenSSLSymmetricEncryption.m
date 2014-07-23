//
//  CTOpenSSLSymmetricEncryption.m
//  CTOpenSSLWrapper
//
//  Created by Oliver Letterer on 05.06.12.
//  Copyright 2012 Home. All rights reserved.
//

#import "CTOpenSSLSymmetricEncryption.h"
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

NSString *NSStringFromCTOpenSSLCipher(CTOpenSSLCipher cipher)
{
    NSString *cipherString = nil;

    switch (cipher) {
        case CTOpenSSLCipherAES256:
            cipherString = @"AES256";
            break;
        default:
            [NSException raise:NSInternalInconsistencyException format:@"CTOpenSSLCipher %d is not supported", cipher];
            break;
    }

    return cipherString;
}

BOOL CTOpenSSLSymmetricEncrypt(CTOpenSSLCipher CTCipher, NSData *symmetricKeyData, NSData *data, NSData **encryptedData)
{
    CTOpenSSLInitialize();

    unsigned char *inputBytes = (unsigned char *)data.bytes;
    int inputLength = (int)data.length;
    unsigned char initializationVector[EVP_MAX_IV_LENGTH];
    int temporaryLength = 0;

    // Perform symmetric encryption...
    unsigned char evp_key[EVP_MAX_KEY_LENGTH] = {"\0"};
    EVP_CIPHER_CTX cipherContext;

    NSString *cipherName = NSStringFromCTOpenSSLCipher(CTCipher);
    const EVP_CIPHER *cipher = EVP_get_cipherbyname(cipherName.UTF8String);

    if (!cipher) {
        NSLog(@"unable to get cipher with name %@", cipherName);
        return NO;
    }

    EVP_BytesToKey(cipher, EVP_md5(), NULL, symmetricKeyData.bytes, (int)symmetricKeyData.length, 1, evp_key, initializationVector);
    EVP_CIPHER_CTX_init(&cipherContext);

    if (!EVP_EncryptInit(&cipherContext, cipher, evp_key, initializationVector)) {
        return NO;
    }
    EVP_CIPHER_CTX_set_key_length(&cipherContext, EVP_MAX_KEY_LENGTH);

    unsigned char *outputBuffer = (unsigned char *)calloc(inputLength + EVP_CIPHER_CTX_block_size(&cipherContext) - 1, sizeof(unsigned char));
    int outputLength = 0;

    if (!outputBuffer) {
        NSLog(@"Cannot allocate memory for buffer!");
        return NO;
    }

    if (!EVP_EncryptUpdate(&cipherContext, outputBuffer, &outputLength, inputBytes, inputLength)) {
        return NO;
    }

    if (!EVP_EncryptFinal(&cipherContext, outputBuffer + outputLength, &temporaryLength)) {
        NSLog(@"EVP_EncryptFinal() failed!");
        return NO;
    }

    outputLength += temporaryLength;
    EVP_CIPHER_CTX_cleanup(&cipherContext);

    *encryptedData = [NSData dataWithBytesNoCopy:outputBuffer length:outputLength freeWhenDone:YES];
    return YES;
}

BOOL CTOpenSSLSymmetricDecrypt(CTOpenSSLCipher CTCipher, NSData *symmetricKeyData, NSData *encryptedData, NSData **decryptedData)
{
    CTOpenSSLInitialize();
    NSCParameterAssert(decryptedData);

    unsigned char *inputBytes = (unsigned char *)encryptedData.bytes;
    unsigned char *outputBuffer = NULL;
    unsigned char initializationVector[EVP_MAX_IV_LENGTH];
    int outputLength = 0;
    int temporaryLength = 0;
    long inputLength = encryptedData.length;

    // Use symmetric decryption...
    unsigned char envelopeKey[EVP_MAX_KEY_LENGTH] = {"\0"};
    EVP_CIPHER_CTX cipherContext;
    const EVP_CIPHER *cipher;

    NSString *cipherName = NSStringFromCTOpenSSLCipher(CTCipher);
    cipher = EVP_get_cipherbyname(cipherName.UTF8String);
    if (!cipher) {
        NSLog(@"unable to get cipher with name %@", cipherName);
        return NO;
    }

    EVP_BytesToKey(cipher, EVP_md5(), NULL, symmetricKeyData.bytes, (int)symmetricKeyData.length, 1, envelopeKey, initializationVector);

    EVP_CIPHER_CTX_init(&cipherContext);

    if (!EVP_DecryptInit(&cipherContext, cipher, envelopeKey, initializationVector)) {
        NSLog(@"EVP_DecryptInit() failed!");
        return NO;
    }
    EVP_CIPHER_CTX_set_key_length(&cipherContext, EVP_MAX_KEY_LENGTH);

    if(EVP_CIPHER_CTX_block_size(&cipherContext) > 1) {
        outputBuffer = (unsigned char *)calloc(inputLength + EVP_CIPHER_CTX_block_size(&cipherContext), sizeof(unsigned char));
    } else {
        outputBuffer = (unsigned char *)calloc(inputLength, sizeof(unsigned char));
    }

    if (!outputBuffer) {
        NSLog(@"Cannot allocate memory for buffer!");
        return NO;
    }

    if (!EVP_DecryptUpdate(&cipherContext, outputBuffer, &outputLength, inputBytes, (int)inputLength)) {
        NSLog(@"EVP_DecryptUpdate() failed!");
        return NO;
    }

    if (!EVP_DecryptFinal(&cipherContext, outputBuffer + outputLength, &temporaryLength)) {
        NSLog(@"EVP_DecryptFinal() failed!");
        return NO;
    }

    outputLength += temporaryLength;
    EVP_CIPHER_CTX_cleanup(&cipherContext);

    *decryptedData = [NSData dataWithBytes:outputBuffer length:outputLength];

    if (outputBuffer) {
        free(outputBuffer);
    }

    return YES;
}
