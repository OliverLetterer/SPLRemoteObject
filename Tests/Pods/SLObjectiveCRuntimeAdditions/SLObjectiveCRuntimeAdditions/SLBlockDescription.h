//
//  SLBlockDescription.h
//  SLBlockDescription
//
//  Created by Oliver Letterer on 01.09.12.
//  Copyright (c) 2012 olettere. All rights reserved.
//

#import <Foundation/Foundation.h>

struct SLBlockLiteral {
    void *isa; // initialized to &_NSConcreteStackBlock or &_NSConcreteGlobalBlock
    int flags;
    int reserved;
    void (*invoke)(void *, ...);
    struct block_descriptor {
        unsigned long int reserved;	// NULL
    	unsigned long int size;         // sizeof(struct Block_literal_1)
        // optional helper functions
    	void (*copy_helper)(void *dst, void *src);     // IFF (1<<25)
    	void (*dispose_helper)(void *src);             // IFF (1<<25)
        // required ABI.2010.3.16
        const char *signature;                         // IFF (1<<30)
    } *descriptor;
    // imported variables
};

enum {
    SLBlockDescriptionFlagsHasCopyDispose = (1 << 25),
    SLBlockDescriptionFlagsHasCtor = (1 << 26), // helpers have C++ code
    SLBlockDescriptionFlagsIsGlobal = (1 << 28),
    SLBlockDescriptionFlagsHasStret = (1 << 29), // IFF BLOCK_HAS_SIGNATURE
    SLBlockDescriptionFlagsHasSignature = (1 << 30)
};
typedef int SLBlockDescriptionFlags;



@interface SLBlockDescription : NSObject

@property (nonatomic, readonly) SLBlockDescriptionFlags flags;
@property (nonatomic, readonly) NSMethodSignature *blockSignature;
@property (nonatomic, readonly) unsigned long int size;
@property (nonatomic, readonly) id block;

- (id)initWithBlock:(id)block;

- (BOOL)blockSignatureIsCompatibleWithMethodSignature:(NSMethodSignature *)methodSignature;

@end
