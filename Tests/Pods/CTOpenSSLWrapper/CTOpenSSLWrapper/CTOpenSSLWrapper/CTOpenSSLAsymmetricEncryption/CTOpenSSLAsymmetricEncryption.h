//
//  CTOpenSSLAsymmetricEncryption.h
//  CTOpenSSLWrapper
//
//  Created by Oliver Letterer on 05.06.12.
//  Copyright 2012 Home. All rights reserved.
//

#import "CTOpenSSLDigest.h"

typedef enum {
    CTOpenSSLPrivateKeyFormatDER = 0,
    CTOpenSSLPrivateKeyFormatPEM
} CTOpenSSLPrivateKeyFormat;

/**
 @abstract  generates a new private key with a given length
 */
NSData *CTOpenSSLGeneratePrivateRSAKey(int keyLength, CTOpenSSLPrivateKeyFormat format);

/**
 @abstract  extracts public key from private key
 */
NSData *CTOpenSSLExtractPublicKeyFromPrivateRSAKey(NSData *privateKeyData);

/**
 @abstract  encrypts data asymmetrically
 @param     publicKeyData: data representing the public key
 @param     data: data to be encrypted
 @return    encrypted data
 */
NSData *CTOpenSSLRSAEncrypt(NSData *publicKeyData, NSData *data);

/**
 @abstract  decrypts data asymmetrically
 @param     privateKeyData: data representing the private key
 @param     data: data to be decrypted
 @return    dectryped data
 */
NSData *CTOpenSSLRSADecrypt(NSData *privateKeyData, NSData *data);

/**
 @abstract  generates signature of data with privateKeyData.
 */
NSData *CTOpenSSLRSASignWithPrivateKey(NSData *privateKeyData, NSData *data, CTOpenSSLDigestType digestType);

/**
 @abstract  vertifies signature with publicKeyData.
 */
BOOL CTOpenSSLRSAVerifyWithPublicKey(NSData *publicKeyData, NSData *data, NSData *signature, CTOpenSSLDigestType digestType);
