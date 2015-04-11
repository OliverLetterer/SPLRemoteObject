//
//  SPLRemoteObjectEncryptionPolicy.h
//  Pods
//
//  Created by Oliver Letterer on 23.07.14.
//  Copyright 2014 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 @abstract  <#abstract comment#>
 */
@protocol SPLRemoteObjectEncryptionPolicy <NSObject>

- (NSData *)dataByEncryptingData:(NSData *)data;
- (NSData *)dataByDescryptingData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
