//
//  SLObjectiveCRuntimeAdditions.h
//  SLObjectiveCRuntimeAdditions
//
//  Created by Oliver Letterer on 28.04.12.
//  Copyright (c) 2012 ebf. All rights reserved.
//

#import <objc/runtime.h>

typedef void(^SLMethodEnumertor)(Class class, Method method);
typedef BOOL(^SLClassTest)(Class subclass);



@protocol SLDynamicSubclassConstructor <NSObject>
- (BOOL)implementInstanceMethodNamed:(SEL)selector implementation:(id)blockImplementation;
- (BOOL)implementInstanceMethodNamed:(SEL)selector types:(const char *)types implementation:(id)blockImplementation;

@end



/**
 @abstract Swizzles originalSelector with newSelector.
 */
void class_swizzleSelector(Class class, SEL originalSelector, SEL newSelector);

/**
 @abstract Swizzles all methods of a class with a given prefix with the corresponding SEL without the prefix. @selector(__hookedLoadView) will be swizzled with @selector(loadView). This method also swizzles class methods with a given prefix.
 */
void class_swizzlesMethodsWithPrefix(Class class, NSString *prefix);

/**
 @abstract Enumerate class methods.
 */
void class_enumerateMethodList(Class class, SLMethodEnumertor enumerator);

/**
 @return A subclass of class which passes test.
 */
Class class_subclassPassingTest(Class class, SLClassTest test);

/**
 @abstract Replaces implementation of method of originalSelector with block.
 if originalSelector's argument list is (id self, SEL _cmd, ...), then block's argument list must be (id self, ...)
 */
IMP class_replaceMethodWithBlock(Class class, SEL originalSelector, id block);

/**
 Implements class property at runtime which is backed by NSUserDefaults. This will use -[NSUserDefaults setObject:forKey:].
 */
void class_implementPropertyInUserDefaults(Class class, NSString *propertyName, BOOL automaticSynchronizeUserDefaults);

/**
 Implements a property at runtime.
 */
void class_implementProperty(Class class, NSString *propertyName);

void class_implementDelayedSetter(Class class, NSTimeInterval delay, SEL getter, SEL setter, SEL action);

/**
 Ensures that `object` is a new dynamic subclass with suffix `_classSuffix`. `constructor` will be used to implement all dynamic subclass methods.
 */
void __attribute__((overloadable)) object_ensureDynamicSubclass(id object, NSString *classSuffix, void(^constructor)(id<SLDynamicSubclassConstructor> constructor));
void __attribute__((overloadable)) object_ensureDynamicSubclass(id object, NSString *classSuffix, BOOL hideDynamicSubclass, void(^constructor)(id<SLDynamicSubclassConstructor> constructor));
