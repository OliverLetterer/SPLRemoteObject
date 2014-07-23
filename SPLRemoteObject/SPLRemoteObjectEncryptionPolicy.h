//
//  SPLRemoteObjectEncryptionPolicy.h
//  Pods
//
//  Created by Oliver Letterer on 23.07.14.
//  Copyright 2014 __MyCompanyName__. All rights reserved.
//

/**
 @abstract  <#abstract comment#>
 */
@protocol SPLRemoteObjectEncryptionPolicy <NSObject>

- (NSData *)dataByEncryptingData:(NSData *)data;
- (NSData *)dataByDescryptingData:(NSData *)data;

@end
