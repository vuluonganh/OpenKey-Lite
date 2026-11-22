//
//  OpenKeyManager.m
//  OpenKey
//
//  Created by Tuyen on 1/27/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#import "OpenKeyManager.h"

extern void OpenKeyInit(void);
extern CGEventRef OpenKeyCallback(CGEventTapProxy proxy,
                                  CGEventType type,
                                  CGEventRef event,
                                  void *refcon);

static BOOL _isInited = NO;
static BOOL _engineReady = NO;
static CFMachPortRef      eventTap;
static CFRunLoopSourceRef runLoopSource;

@implementation OpenKeyManager

+(BOOL)isInited {
    return _isInited;
}

+(BOOL)initEventTap {
    if (_isInited)
        return YES;

    if (!_engineReady) {
        OpenKeyInit();
        _engineReady = YES;
    }

    // Key down drives the engine, flags changed drives the switch shortcut,
    // and a mouse click ends the current word.
    CGEventMask eventMask = ((1 << kCGEventKeyDown) |
                             (1 << kCGEventFlagsChanged) |
                             (1 << kCGEventLeftMouseDown) |
                             (1 << kCGEventRightMouseDown));

    eventTap = CGEventTapCreate(kCGSessionEventTap,
                                kCGHeadInsertEventTap,
                                kCGEventTapOptionDefault,
                                eventMask,
                                OpenKeyCallback,
                                NULL);
    if (!eventTap) {
        NSLog(@"OpenKey Lite: could not create the event tap (Accessibility permission missing?)");
        return NO;
    }

    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(eventTap, true);
    _isInited = YES;
    return YES;
}

+(BOOL)stopEventTap {
    if (_isInited) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);
        runLoopSource = nil;

        CFMachPortInvalidate(eventTap);
        CFRelease(eventTap);
        eventTap = nil;

        _isInited = NO;
    }
    return YES;
}

+(void)reenableEventTap {
    if (eventTap)
        CGEventTapEnable(eventTap, true);
}

@end
