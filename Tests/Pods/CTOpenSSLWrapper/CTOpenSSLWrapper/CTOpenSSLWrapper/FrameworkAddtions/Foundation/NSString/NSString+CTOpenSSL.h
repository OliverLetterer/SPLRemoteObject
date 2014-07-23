//
//  NSString+CTOpenSSL.h
//  CTOpenSSLWrapper
//
//  Created by Oliver Letterer on 06.06.12.
//  Copyright (c) 2012 Home. All rights reserved.
//

@interface NSString (CTOpenSSL)

@property (nonatomic, readonly) NSData *dataFromHexadecimalString;
@property (nonatomic, readonly) NSData *dataFromBase64EncodedString;

@property (nonatomic, readonly) NSString *MD5Digest;
@property (nonatomic, readonly) NSString *SHA512Digest;

@end
