//
//  AppDelegate.h
//  OpenKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//
//  Menu bar app: status icon + a small menu. No windows.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>

//switch between Vietnamese (YES) and English (NO); saves it and updates the icon
-(void)setVietnamese:(BOOL)on;

@end

extern AppDelegate* appDelegate;
