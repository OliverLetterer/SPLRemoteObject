//
//  NSData+CTOpenSSL.h
//  CTOpenSSLWrapper
//
//  Created by Oliver Letterer on 04.06.12.
//  Copyright (c) 2012 Home. All rights reserved.
//

@interface NSData (CTOpenSSL)

@property (nonatomic, readonly) NSString *base64EncodedString;
- (NSString *)base64EncodedStringWithNewLines:(BOOL)useNewLines;

@property (nonatomic, readonly) NSString *hexadecimalValue;

@end
