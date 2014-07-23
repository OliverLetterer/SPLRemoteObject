//
//  SPLRemoteObjectBase.h
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

typedef void(^SPLRemoteObjectErrorBlock)(NSError *error);
typedef NSData *(^SPLRemoteObjectDataEncryptionBlock)(NSData *rawData, NSData *symmetricKey);
typedef NSData *(^SPLRemoteObjectDataDecryptionBlock)(NSData *encryptedData, NSData *symmetricKey);



/**
 Reachability
 */
typedef enum {
    SPLRemoteObjectReachabilityStatusUnavailable = 0,
    SPLRemoteObjectReachabilityStatusAvailable
} SPLRemoteObjectReachabilityStatus;



/**
 Getting posted when a network operation starts or ends
 */
extern NSString *const SPLRemoteObjectNetworkOperationDidStartNotification;
extern NSString *const SPLRemoteObjectNetworkOperationDidEndNotification;



/**
 SPLRemoteObject options
 */
extern NSString *const SPLRemoteObjectEncryptionType;

typedef NS_OPTIONS(NSUInteger, SPLRemoteObjectEncryption) {
    SPLRemoteObjectEncryptionNone         = 0,
    SPLRemoteObjectEncryptionSymmetric    = 1,
    SPLRemoteObjectEncryptionSSL          = 2
};

/**
 symmetric encryption
 */
extern NSString *const SPLRemoteObjectSymmetricKey;
extern NSString *const SPLRemoteObjectSymmetricEncryptionBlock;
extern NSString *const SPLRemoteObjectSymmetricDecryptionBlock;


/**
 SSL options
 */
extern NSString *const SPLRemoteObjectSSLSecIdentityRef;
extern NSString *const SPLRemoteObjectSSLPeerDomainName;



/**
 SPLRemoteObject errors
 */
extern NSString *const SPLRemoteObjectErrorDomain;

typedef enum {
    SPLRemoteObjectConnectionFailed = 1000,
    SPLRemoteObjectConnectionTimedOut = 1001,
    SPLRemoteObjectConnectionIncompatibleProtocol = 1002
} SPLRemoteObjectErrorCode;
