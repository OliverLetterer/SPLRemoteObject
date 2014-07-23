//
//  NSString+CTOpenSSL.m
//  CTOpenSSLWrapper
//
//  Created by Oliver Letterer on 06.06.12.
//  Copyright (c) 2012 Home. All rights reserved.
//

#import "NSString+CTOpenSSL.h"
#import "CTOpenSSLDigest.h"
#import "NSData+CTOpenSSL.h"

static const short CTBase64DecodingTable[256] = {
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -1, -1, -2, -1, -1, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2,
    -1, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, 62, -2, -2, -2, 63,
    52, 53, 54, 55, 56, 57, 58, 59, 60, 61, -2, -2, -2, -2, -2, -2,
    -2,  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14,
    15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, -2, -2, -2, -2, -2,
    -2, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
    41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, -2, -2, -2, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2
};

@implementation NSString (CTOpenSSL)

- (NSData *)dataFromHexadecimalString
{
    const char *bytes = [self cStringUsingEncoding:NSUTF8StringEncoding];
    NSUInteger length = strlen(bytes);
    unsigned char *dataBuffer = (unsigned char *)malloc(length / 2 + 1);
    unsigned char *index = dataBuffer;

    while ((*bytes) && (*(bytes + 1))) {
        char encoder[3] = {'\0', '\0', '\0'};
        encoder[0] = *bytes;
        encoder[1] = *(bytes + 1);
        *index = strtol(encoder, NULL, 16);
        index++;
        bytes+=2;
    }
    *index = '\0';

    return [NSData dataWithBytesNoCopy:dataBuffer length:length / 2 freeWhenDone:YES];
}

- (NSData *)dataFromBase64EncodedString
{
    const char * objPointer = [self cStringUsingEncoding:NSASCIIStringEncoding];
    size_t intLength = strlen(objPointer);
    int intCurrent;
    int i = 0, j = 0, k;

    unsigned char * objResult;
    objResult = calloc(intLength, sizeof(unsigned char));

    // Run through the whole string, converting as we go
    while ( ((intCurrent = *objPointer++) != '\0') && (intLength-- > 0) ) {
        if (intCurrent == '=') {
            if (*objPointer != '=' && ((i % 4) == 1)) {// || (intLength > 0)) {
                // the padding character is invalid at this point -- so this entire string is invalid
                free(objResult);
                return nil;
            }
            continue;
        }

        intCurrent = CTBase64DecodingTable[intCurrent];
        if (intCurrent == -1) {
            // we're at a whitespace -- simply skip over
            continue;
        } else if (intCurrent == -2) {
            // we're at an invalid character
            free(objResult);
            return nil;
        }

        switch (i % 4) {
            case 0:
                objResult[j] = intCurrent << 2;
                break;

            case 1:
                objResult[j++] |= intCurrent >> 4;
                objResult[j] = (intCurrent & 0x0f) << 4;
                break;

            case 2:
                objResult[j++] |= intCurrent >>2;
                objResult[j] = (intCurrent & 0x03) << 6;
                break;

            case 3:
                objResult[j++] |= intCurrent;
                break;
        }
        i++;
    }

    // mop things up if we ended on a boundary
    k = j;
    if (intCurrent == '=') {
        switch (i % 4) {
            case 1:
                // Invalid state
                free(objResult);
                return nil;

            case 2:
                k++;
                // flow through
            case 3:
                objResult[k] = 0;
        }
    }

    // Cleanup and setup the return NSData
    NSData * objData = [[NSData alloc] initWithBytes:objResult length:j];
    free(objResult);
    return objData;
}


- (NSString *)MD5Digest
{
    return CTOpenSSLGenerateDigestFromData([self dataUsingEncoding:NSUTF8StringEncoding], CTOpenSSLDigestTypeMD5).hexadecimalValue;
}

- (NSString *)SHA512Digest
{
    return CTOpenSSLGenerateDigestFromData([self dataUsingEncoding:NSUTF8StringEncoding], CTOpenSSLDigestTypeSHA512).hexadecimalValue;
}

@end
