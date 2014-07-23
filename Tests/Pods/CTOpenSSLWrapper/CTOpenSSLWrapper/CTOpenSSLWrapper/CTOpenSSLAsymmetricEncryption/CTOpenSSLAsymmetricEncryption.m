//
//  CTOpenSSLAsymmetricEncryption.m
//  CTOpenSSLWrapper
//
//  Created by Oliver Letterer on 05.06.12.
//  Copyright 2012 Home. All rights reserved.
//

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

NSData *CTOpenSSLGeneratePrivateRSAKey(int keyLength, CTOpenSSLPrivateKeyFormat format)
{
    CTOpenSSLInitialize();

    BIGNUM *someBigNumber = BN_new();
    RSA *key = RSA_new();

    BN_set_word(someBigNumber, RSA_F4);

    if (!RSA_generate_key_ex(key, keyLength, someBigNumber, NULL)) {
        [NSException raise:NSInternalInconsistencyException format:@"RSA_generate_key_ex() failed"];
    }

    BIO *bio = BIO_new(BIO_s_mem());

	switch (format) {
		case CTOpenSSLPrivateKeyFormatDER:
			i2d_RSAPrivateKey_bio(bio, key);
			break;
		case CTOpenSSLPrivateKeyFormatPEM:
			PEM_write_bio_RSAPrivateKey(bio, key, NULL, NULL, 0, NULL, NULL);
			break;
		default:
			return nil;
	}

    char *bioData = NULL;
    long bioDataLength = BIO_get_mem_data(bio, &bioData);
    NSData *result = [NSData dataWithBytes:bioData length:bioDataLength];

    RSA_free(key);
    BN_free(someBigNumber);
    BIO_free(bio);

    return result;
}

NSData *CTOpenSSLExtractPublicKeyFromPrivateRSAKey(NSData *privateKeyData)
{
    CTOpenSSLInitialize();

    BIO *privateBIO = NULL;
	RSA *privateRSA = NULL;

	if (!(privateBIO = BIO_new_mem_buf((unsigned char*)privateKeyData.bytes, (int)privateKeyData.length))) {
        [NSException raise:NSInternalInconsistencyException format:@"cannot allocate new BIO memory buffer"];
	}

	if (!PEM_read_bio_RSAPrivateKey(privateBIO, &privateRSA, NULL, NULL)) {
        [NSException raise:NSInternalInconsistencyException format:@"cannot read private RSA BIO with PEM_read_bio_RSAPrivateKey()!"];
	}

	int RSAKeyError = RSA_check_key(privateRSA);
	if (RSAKeyError != 1) {
        [NSException raise:NSInternalInconsistencyException format:@"private RSA key is invalid: %d", RSAKeyError];
	}

    BIO *bio = BIO_new(BIO_s_mem());

    if (!PEM_write_bio_RSA_PUBKEY(bio, privateRSA)) {
        [NSException raise:NSInternalInconsistencyException format:@"unable to write public key"];
        return nil;
    }

    char *bioData = NULL;
    long bioDataLength = BIO_get_mem_data(bio, &bioData);
    NSData *result = [NSData dataWithBytes:bioData length:bioDataLength];

    RSA_free(privateRSA);
    BIO_free(bio);

    return result;
}

NSData *CTOpenSSLRSAEncrypt(NSData *publicKeyData, NSData *data)
{
    CTOpenSSLInitialize();

    unsigned char *inputBytes = (unsigned char *)data.bytes;
    long inputLength = data.length;

    BIO *publicBIO = NULL;
    RSA *publicRSA = NULL;

    if (!(publicBIO = BIO_new_mem_buf((unsigned char *)publicKeyData.bytes, (int)publicKeyData.length))) {
        [NSException raise:NSInternalInconsistencyException format:@"cannot allocate new BIO memory buffer"];
    }

    if (!PEM_read_bio_RSA_PUBKEY(publicBIO, &publicRSA, NULL, NULL)) {
        [NSException raise:NSInternalInconsistencyException format:@"cannot read public RSA BIO with PEM_read_bio_RSA_PUBKEY()!"];
    }

    unsigned char *outputBuffer = (unsigned char *)malloc(RSA_size(publicRSA));
    int outputLength = 0;

    if (!(outputLength = RSA_public_encrypt((int)inputLength, inputBytes, (unsigned char *)outputBuffer, publicRSA, RSA_PKCS1_PADDING))) {
        [NSException raise:NSInternalInconsistencyException format:@"RSA public encryption RSA_public_encrypt() failed"];
    }

    if (outputLength == -1) {
        [NSException raise:NSInternalInconsistencyException format:@"Encryption failed with error %s (%s)", ERR_error_string(ERR_get_error(), NULL), ERR_reason_error_string(ERR_get_error())];
    }

    NSData *encryptedData = [NSData dataWithBytesNoCopy:outputBuffer length:outputLength freeWhenDone:YES];

    BIO_free(publicBIO);
    RSA_free(publicRSA);

    return encryptedData;
}

NSData *CTOpenSSLRSADecrypt(NSData *privateKeyData, NSData *data)
{
    CTOpenSSLInitialize();

    unsigned char *inputBytes = (unsigned char *)data.bytes;
    long inputLength = data.length;

    BIO *privateBIO = NULL;
    RSA *privateRSA = NULL;

    if (!(privateBIO = BIO_new_mem_buf((unsigned char*)privateKeyData.bytes, (int)privateKeyData.length))) {
        [NSException raise:NSInternalInconsistencyException format:@"cannot allocate new BIO memory buffer"];
    }

    if (!PEM_read_bio_RSAPrivateKey(privateBIO, &privateRSA, NULL, NULL)) {
        [NSException raise:NSInternalInconsistencyException format:@"cannot read private RSA BIO with PEM_read_bio_RSAPrivateKey()!"];
    }

    int RSAKeyError = RSA_check_key(privateRSA);
    if (RSAKeyError != 1) {
        [NSException raise:NSInternalInconsistencyException format:@"private RSA key is invalid: %d", RSAKeyError];
    }

    unsigned char *outputBuffer = (unsigned char *)malloc(RSA_size(privateRSA));
    int outputLength = 0;

    if (!(outputLength = RSA_private_decrypt((int)inputLength, inputBytes, outputBuffer, privateRSA, RSA_PKCS1_PADDING))) {
        [NSException raise:NSInternalInconsistencyException format:@"RSA private decrypt RSA_private_decrypt() failed"];
    }

    if (outputLength == -1) {
        [NSException raise:NSInternalInconsistencyException format:@"Encryption failed with error %s (%s)", ERR_error_string(ERR_get_error(), NULL), ERR_reason_error_string(ERR_get_error())];
    }

    NSData *decryptedData = [NSData dataWithBytesNoCopy:outputBuffer length:outputLength freeWhenDone:YES];

    BIO_free(privateBIO);
    RSA_free(privateRSA);

    return decryptedData;
}

NSData *CTOpenSSLRSASignWithPrivateKey(NSData *privateKeyData, NSData *data, CTOpenSSLDigestType digestType)
{
    CTOpenSSLInitialize();

    data = CTOpenSSLGenerateDigestFromData(data, digestType);

    unsigned char *inputBytes = (unsigned char *)data.bytes;
    long inputLength = data.length;

    BIO *privateBIO = NULL;
    RSA *privateRSA = NULL;

    if (!(privateBIO = BIO_new_mem_buf((unsigned char*)privateKeyData.bytes, (int)privateKeyData.length))) {
        [NSException raise:NSInternalInconsistencyException format:@"cannot allocate new BIO memory buffer"];
    }

    if (!PEM_read_bio_RSAPrivateKey(privateBIO, &privateRSA, NULL, NULL)) {
        [NSException raise:NSInternalInconsistencyException format:@"cannot read private RSA BIO with PEM_read_bio_RSAPrivateKey()!"];
    }

    int RSAKeyError = RSA_check_key(privateRSA);
    if (RSAKeyError != 1) {
        [NSException raise:NSInternalInconsistencyException format:@"private RSA key is invalid: %d", RSAKeyError];
    }

    unsigned char *outputBuffer = (unsigned char *)malloc(RSA_size(privateRSA));
    unsigned int outputLength = 0;

    int type = CTOpenSSLRSASignTypeFromDigestType(digestType);

    if (!RSA_sign(type, inputBytes, (unsigned int)inputLength, outputBuffer, &outputLength, privateRSA)) {
        [NSException raise:NSInternalInconsistencyException format:@"RSA_sign() failed"];
    }

    if (outputLength == -1) {
        [NSException raise:NSInternalInconsistencyException format:@"Encryption failed with error %s (%s)", ERR_error_string(ERR_get_error(), NULL), ERR_reason_error_string(ERR_get_error())];
    }

    NSData *decryptedData = [NSData dataWithBytesNoCopy:outputBuffer length:outputLength freeWhenDone:YES];

    BIO_free(privateBIO);
    RSA_free(privateRSA);

    return decryptedData;
}

BOOL CTOpenSSLRSAVerifyWithPublicKey(NSData *publicKeyData, NSData *data, NSData *signature, CTOpenSSLDigestType digestType)
{
    CTOpenSSLInitialize();

    data = CTOpenSSLGenerateDigestFromData(data, digestType);

    unsigned char *inputBytes = (unsigned char *)data.bytes;
    long inputLength = data.length;

    unsigned char *signatureBytes = (unsigned char *)signature.bytes;
    long signatureLength = signature.length;

    BIO *publicBIO = NULL;
    RSA *publicRSA = NULL;

    if (!(publicBIO = BIO_new_mem_buf((unsigned char *)publicKeyData.bytes, (int)publicKeyData.length))) {
        [NSException raise:NSInternalInconsistencyException format:@"cannot allocate new BIO memory buffer"];
    }

    if (!PEM_read_bio_RSA_PUBKEY(publicBIO, &publicRSA, NULL, NULL)) {
        [NSException raise:NSInternalInconsistencyException format:@"cannot read public RSA BIO with PEM_read_bio_RSA_PUBKEY()!"];
    }

    int type = CTOpenSSLRSASignTypeFromDigestType(digestType);

    BOOL signatureIsVerified = RSA_verify(type, inputBytes, (unsigned int)inputLength, signatureBytes, (unsigned int)signatureLength, publicRSA) == 1;

    BIO_free(publicBIO);
    RSA_free(publicRSA);

    return signatureIsVerified;
}
