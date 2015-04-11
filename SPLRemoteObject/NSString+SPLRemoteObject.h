//
//  NSString+SPLRemoteObject.h
//  Pods
//
//  Created by Oliver Letterer on 23.07.14.
//  Copyright (c) 2014 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSString (SPLRemoteObject)

- (NSString *)netServiceTypeWithProtocol:(Protocol *)protocol;

@end

NS_ASSUME_NONNULL_END
