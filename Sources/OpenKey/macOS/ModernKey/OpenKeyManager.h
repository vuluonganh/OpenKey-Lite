//
//  OpenKeyManager.h
//  OpenKey
//
//  Created by Tuyen on 1/27/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//
//  Owns the keyboard event tap.
//

#import <Cocoa/Cocoa.h>

@interface OpenKeyManager : NSObject
+(BOOL)isInited;
+(BOOL)initEventTap;
+(BOOL)stopEventTap;
+(void)reenableEventTap;
@end
