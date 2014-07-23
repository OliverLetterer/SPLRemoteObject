//
//  SPLRemoteObjectBrowser.h
//  Pods
//
//  Created by Oliver Letterer on 23.07.14.
//  Copyright 2014 __MyCompanyName__. All rights reserved.
//



/**
 @abstract  <#abstract comment#>
 */
@interface SPLRemoteObjectBrowser : NSObject 

@property (nonatomic, readonly) NSString *type;
@property (nonatomic, readonly) Protocol *protocol;

@property (nonatomic, readonly) NSArray *remoteObjects;

- (instancetype)init UNAVAILABLE_ATTRIBUTE;
- (instancetype)initWithType:(NSString *)type protocol:(Protocol *)protocol;

@end
