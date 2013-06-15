//
//  SLEmptyClass.m
//  SLRemoteObject
//
//  Created by Oliver Letterer on 15.06.13.
//  Copyright 2013 Sparrow-Labs. All rights reserved.
//

#import "SLEmptyClass.h"



@interface SLEmptyClass () {
    
}

@end



@implementation SLEmptyClass

#pragma mark - Initialization

- (id)init 
{
    if (self = [super init]) {
        // Initialization code
    }
    return self;
}

#pragma mark - Memory management

- (void)dealloc
{
    
}

#pragma mark - Private category implementation ()

@end
