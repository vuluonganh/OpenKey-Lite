//
//  AppDelegate.m
//  OpenKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#import <ServiceManagement/ServiceManagement.h>
#import <ApplicationServices/ApplicationServices.h>
#import <libproc.h>
#import "AppDelegate.h"
#import "OpenKeyManager.h"

AppDelegate* appDelegate;

extern void RequestNewSession(void);
extern void InvalidateSpotlightState(void);

//switch shortcut layout (see Engine.h): bits 0-7 key code, 8 ⌃, 9 ⌥, 10 ⌘, 11 ⇧, 15 beep,
//bits 24-31 the key's character for display
#define DEFAULT_SWITCH_STATUS 0x7A000206 //option + z
#define SWITCH_CONTROL 0x100
#define SWITCH_OPTION 0x200
#define SWITCH_COMMAND 0x400
#define SWITCH_SHIFT 0x800
#define SWITCH_BEEP 0x8000
#define SWITCH_KEY_MODIFIERS_ONLY 0xFE

//settings shared with the engine (see Engine.h)
int vLanguage = 1;
int vSwitchKeyStatus = DEFAULT_SWITCH_STATUS;
int vUseModernOrthography = 0;
int vRestoreIfWrongSpelling = 0;

//saved settings (keys kept from earlier versions so existing settings carry over)
static NSString* const kPrefLanguage = @"InputMethod";
static NSString* const kPrefSwitchKey = @"SwitchKeyStatus";
static NSString* const kPrefModernTones = @"ModernOrthography";
static NSString* const kPrefKeepNonVietnamese = @"RestoreIfInvalidWord";
static NSString* const kPrefRunAtLogin = @"RunOnStartup";
static NSString* const kPrefLoginItemSet = @"LoginItemSet";

//opens the Accessibility list (macOS 27 calls it "Device Control and Data Access")
static NSString* const kAccessibilitySettingsURL = @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility";

#pragma mark - Status icon

//A rounded key cap with the mode's letter: filled with a cut-out "V" for Vietnamese,
//outlined "E" for English. Template image, so it follows the menu bar's appearance.
static NSImage* StatusIcon(NSString* letter, BOOL filled, CGFloat alpha) {
    NSImage* image = [NSImage imageWithSize:NSMakeSize(19, 15) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        NSRect box = NSInsetRect(rect, 1.5, 1.0);
        NSColor* ink = [NSColor colorWithWhite:0 alpha:alpha];
        NSFont* font = [NSFont systemFontOfSize:10 weight:NSFontWeightBold];
        NSDictionary* attributes = @{NSFontAttributeName: font, NSForegroundColorAttributeName: ink};
        NSSize size = [letter sizeWithAttributes:attributes];
        //center the capital letter optically: its baseline sits half a cap height below the middle
        NSPoint origin = NSMakePoint(round((NSMidX(box) - size.width / 2) * 2) / 2,
                                     NSMidY(box) - font.capHeight / 2 + font.descender);
        if (filled) {
            [ink setFill];
            [[NSBezierPath bezierPathWithRoundedRect:box xRadius:3.5 yRadius:3.5] fill];
            [NSGraphicsContext.currentContext setCompositingOperation:NSCompositingOperationDestinationOut];
            [letter drawAtPoint:origin withAttributes:attributes];
            [NSGraphicsContext.currentContext setCompositingOperation:NSCompositingOperationSourceOver];
        } else {
            NSBezierPath* outline = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(box, 0.6, 0.6) xRadius:3 yRadius:3];
            outline.lineWidth = 1.2;
            [ink setStroke];
            [outline stroke];
            [letter drawAtPoint:origin withAttributes:attributes];
        }
        return YES;
    }];
    image.template = YES;
    return image;
}

@implementation AppDelegate {
    NSStatusItem* _statusItem;
    NSMenu* _menu;
    NSMenuItem* _vietnameseItem;
    NSMenuItem* _modernTonesItem;
    NSMenuItem* _keepNonVietnameseItem;
    NSMenuItem* _beepItem;
    NSMenuItem* _loginItem;
    NSTimer* _permissionTimer;
}

#pragma mark - Launch

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    appDelegate = self;

    if ([self isAlreadyRunning]) {
        [NSApp terminate:nil];
        return;
    }

    [self loadSettings];
    [self syncLoginItemOnFirstRun];

    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _menu = [[NSMenu alloc] initWithTitle:@""];
    _menu.delegate = self;
    _statusItem.menu = _menu;

    [self registerWorkspaceNotifications];

    //ask macOS for Accessibility permission (shows the system prompt once)
    NSDictionary* options = @{(__bridge NSString*)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    [self startTypingWhenPermitted];
}

//only one OpenKey per user (another user's OpenKey may run under fast user switching)
- (BOOL)isAlreadyRunning {
    uid_t currentUID = getuid();
    pid_t myPID = [[NSProcessInfo processInfo] processIdentifier];
    NSString* myBundleID = [[NSBundle mainBundle] bundleIdentifier];
    for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
        if ([app.bundleIdentifier isEqualToString:myBundleID] && app.processIdentifier != myPID) {
            struct proc_bsdinfo proc;
            int size = proc_pidinfo(app.processIdentifier, PROC_PIDTBSDINFO, 0, &proc, sizeof(proc));
            if (size == sizeof(proc) && proc.pbi_uid == currentUID)
                return YES;
        }
    }
    return NO;
}

- (void)loadSettings {
    NSUserDefaults* prefs = [NSUserDefaults standardUserDefaults];
    [prefs registerDefaults:@{kPrefLanguage: @1,
                              kPrefSwitchKey: @(DEFAULT_SWITCH_STATUS),
                              kPrefModernTones: @0,
                              kPrefKeepNonVietnamese: @0,
                              kPrefRunAtLogin: @1}];
    vLanguage = [prefs integerForKey:kPrefLanguage] ? 1 : 0;
    vSwitchKeyStatus = (int)[prefs integerForKey:kPrefSwitchKey];
    if (vSwitchKeyStatus == 0)
        vSwitchKeyStatus = DEFAULT_SWITCH_STATUS;
    vUseModernOrthography = [prefs integerForKey:kPrefModernTones] ? 1 : 0;
    vRestoreIfWrongSpelling = [prefs integerForKey:kPrefKeepNonVietnamese] ? 1 : 0;
}

//start the keyboard tap now if macOS allows it; otherwise show the waiting menu and keep
//retrying quietly, so typing starts as soon as permission is granted, without a relaunch.
//(the permission flag can turn on a moment before macOS lets a tap be created, so retry
//until the tap itself starts, not just until the flag is set)
- (void)startTypingWhenPermitted {
    if ([self tryStartTyping])
        return;
    [self buildMenu];
    if (_permissionTimer == nil) {
        __weak AppDelegate* weakSelf = self;
        _permissionTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer* timer) {
            [weakSelf tryStartTyping];
        }];
    }
}

- (BOOL)tryStartTyping {
    if (!AXIsProcessTrusted() || ![OpenKeyManager initEventTap])
        return NO;
    [_permissionTimer invalidate];
    _permissionTimer = nil;
    [self buildMenu];
    return YES;
}

#pragma mark - Menu

- (void)buildMenu {
    [_menu removeAllItems];
    _menu.autoenablesItems = NO;
    _vietnameseItem = _modernTonesItem = _keepNonVietnameseItem = _beepItem = _loginItem = nil;

    if (![OpenKeyManager isInited]) {
        NSMenuItem* info = [_menu addItemWithTitle:@"OpenKey Lite cần được cấp quyền để gõ tiếng Việt" action:nil keyEquivalent:@""];
        info.enabled = NO;
        [self addItem:@"Cấp quyền cho OpenKey Lite…" action:@selector(openAccessibilitySettings)];
        [_menu addItem:[NSMenuItem separatorItem]];
        [self addItem:@"Thoát OpenKey Lite" action:@selector(terminate:) key:@"q" target:NSApp];
        [self updateStatusIcon];
        return;
    }

    _vietnameseItem = [self addItem:@"Gõ tiếng Việt" action:@selector(toggleVietnamese)];
    [self showSwitchShortcutOnItem:_vietnameseItem];

    [_menu addItem:[NSMenuItem separatorItem]];
    _modernTonesItem = [self addItem:@"Đặt dấu kiểu mới: hoà, uý" action:@selector(toggleModernTones)];
    _modernTonesItem.toolTip = @"Tắt để đặt dấu kiểu cũ: hòa, úy";
    _keepNonVietnameseItem = [self addItem:@"Giữ nguyên từ không phải tiếng Việt" action:@selector(toggleKeepNonVietnamese)];
    _keepNonVietnameseItem.toolTip = @"Ví dụ: gõ “windows” vẫn ra “windows”, không thành “ưindows”";
    _beepItem = [self addItem:@"Kêu bíp khi chuyển chế độ" action:@selector(toggleBeep)];

    [_menu addItem:[NSMenuItem separatorItem]];
    _loginItem = [self addItem:@"Mở cùng macOS" action:@selector(toggleLaunchAtLogin)];

    [_menu addItem:[NSMenuItem separatorItem]];
    [self addItem:@"Thoát OpenKey Lite" action:@selector(terminate:) key:@"q" target:NSApp];

    [self refreshMenuState];
}

- (NSMenuItem*)addItem:(NSString*)title action:(SEL)action {
    return [self addItem:title action:action key:@"" target:self];
}

- (NSMenuItem*)addItem:(NSString*)title action:(SEL)action key:(NSString*)key target:(id)target {
    NSMenuItem* item = [_menu addItemWithTitle:title action:action keyEquivalent:key];
    item.target = target;
    return item;
}

//show the switch shortcut next to "Gõ tiếng Việt", e.g. ⌃Z
- (void)showSwitchShortcutOnItem:(NSMenuItem*)item {
    NSEventModifierFlags modifiers = 0;
    if (vSwitchKeyStatus & SWITCH_CONTROL) modifiers |= NSEventModifierFlagControl;
    if (vSwitchKeyStatus & SWITCH_OPTION) modifiers |= NSEventModifierFlagOption;
    if (vSwitchKeyStatus & SWITCH_COMMAND) modifiers |= NSEventModifierFlagCommand;
    if (vSwitchKeyStatus & SWITCH_SHIFT) modifiers |= NSEventModifierFlagShift;

    unichar keyChar = (vSwitchKeyStatus >> 24) & 0xFF;
    if ((vSwitchKeyStatus & 0xFF) == SWITCH_KEY_MODIFIERS_ONLY || keyChar < 0x21 || keyChar > 0x7E) {
        //modifier-only shortcut (or no printable key): spell it out in the title
        NSMutableString* symbols = [NSMutableString string];
        if (modifiers & NSEventModifierFlagControl) [symbols appendString:@"⌃"];
        if (modifiers & NSEventModifierFlagOption) [symbols appendString:@"⌥"];
        if (modifiers & NSEventModifierFlagShift) [symbols appendString:@"⇧"];
        if (modifiers & NSEventModifierFlagCommand) [symbols appendString:@"⌘"];
        if (symbols.length > 0)
            item.title = [NSString stringWithFormat:@"%@    %@", item.title, symbols];
        return;
    }
    item.keyEquivalent = [[NSString stringWithCharacters:&keyChar length:1] lowercaseString];
    item.keyEquivalentModifierMask = modifiers;
}

- (void)refreshMenuState {
    _vietnameseItem.state = vLanguage ? NSControlStateValueOn : NSControlStateValueOff;
    _modernTonesItem.state = vUseModernOrthography ? NSControlStateValueOn : NSControlStateValueOff;
    _keepNonVietnameseItem.state = vRestoreIfWrongSpelling ? NSControlStateValueOn : NSControlStateValueOff;
    _beepItem.state = (vSwitchKeyStatus & SWITCH_BEEP) ? NSControlStateValueOn : NSControlStateValueOff;
    _loginItem.state = [self isLaunchAtLoginOn] ? NSControlStateValueOn : NSControlStateValueOff;
    [self updateStatusIcon];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    //the login item can also be changed in System Settings
    [self refreshMenuState];
}

- (void)updateStatusIcon {
    NSButton* button = _statusItem.button;
    if (![OpenKeyManager isInited]) {
        button.image = StatusIcon(@"V", NO, 0.45);
        button.toolTip = @"OpenKey Lite cần được cấp quyền";
        return;
    }
    button.image = vLanguage ? StatusIcon(@"V", YES, 1) : StatusIcon(@"E", NO, 1);
    button.toolTip = vLanguage ? @"OpenKey Lite: Tiếng Việt" : @"OpenKey Lite: English";
}

#pragma mark - Actions

- (void)setVietnamese:(BOOL)on {
    vLanguage = on ? 1 : 0;
    [[NSUserDefaults standardUserDefaults] setInteger:vLanguage forKey:kPrefLanguage];
    RequestNewSession();
    [self refreshMenuState];
}

- (void)toggleVietnamese {
    [self setVietnamese:!vLanguage];
}

- (void)toggleModernTones {
    vUseModernOrthography = !vUseModernOrthography;
    [[NSUserDefaults standardUserDefaults] setInteger:vUseModernOrthography forKey:kPrefModernTones];
    [self refreshMenuState];
}

- (void)toggleKeepNonVietnamese {
    vRestoreIfWrongSpelling = !vRestoreIfWrongSpelling;
    [[NSUserDefaults standardUserDefaults] setInteger:vRestoreIfWrongSpelling forKey:kPrefKeepNonVietnamese];
    [self refreshMenuState];
}

- (void)toggleBeep {
    vSwitchKeyStatus ^= SWITCH_BEEP;
    [[NSUserDefaults standardUserDefaults] setInteger:vSwitchKeyStatus forKey:kPrefSwitchKey];
    [self refreshMenuState];
}

- (void)toggleLaunchAtLogin {
    [self setLaunchAtLogin:![self isLaunchAtLoginOn]];
    [self refreshMenuState];
}

- (void)openAccessibilitySettings {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kAccessibilitySettingsURL]];
}

#pragma mark - Launch at login

- (BOOL)isLaunchAtLoginOn {
    SMAppServiceStatus status = [SMAppService mainAppService].status;
    return status == SMAppServiceStatusEnabled || status == SMAppServiceStatusRequiresApproval;
}

//register OpenKey itself as a login item (no helper app needed)
- (void)setLaunchAtLogin:(BOOL)on {
    SMAppService *service = [SMAppService mainAppService];
    NSError *error = nil;
    if (on) {
        if (![self isLaunchAtLoginOn] && ![service registerAndReturnError:&error])
            NSLog(@"OpenKey Lite: could not register login item: %@", error);
        //macOS may ask the user to allow it in System Settings → Login Items
        if (service.status == SMAppServiceStatusRequiresApproval)
            [SMAppService openSystemSettingsLoginItems];
    } else if (service.status != SMAppServiceStatusNotRegistered && service.status != SMAppServiceStatusNotFound) {
        if (![service unregisterAndReturnError:&error])
            NSLog(@"OpenKey Lite: could not unregister login item: %@", error);
    }
    NSUserDefaults* prefs = [NSUserDefaults standardUserDefaults];
    [prefs setInteger:on ? 1 : 0 forKey:kPrefRunAtLogin];
    [prefs setBool:YES forKey:kPrefLoginItemSet];
}

//turn the saved "open at login" choice into a login item once; after that the
//login item itself is the source of truth, so removing it in System Settings sticks
- (void)syncLoginItemOnFirstRun {
    NSUserDefaults* prefs = [NSUserDefaults standardUserDefaults];
    if (![prefs boolForKey:kPrefLoginItemSet] && [prefs integerForKey:kPrefRunAtLogin])
        [self setLaunchAtLogin:YES];
}

#pragma mark - System events

- (void)registerWorkspaceNotifications {
    NSNotificationCenter* center = [[NSWorkspace sharedWorkspace] notificationCenter];
    [center addObserver:self selector:@selector(systemWillSleep:) name:NSWorkspaceWillSleepNotification object:nil];
    [center addObserver:self selector:@selector(systemDidWake:) name:NSWorkspaceDidWakeNotification object:nil];
    [center addObserver:self selector:@selector(activeSpaceChanged:) name:NSWorkspaceActiveSpaceDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(activeAppChanged:) name:NSWorkspaceDidActivateApplicationNotification object:nil];
}

- (void)systemWillSleep:(NSNotification*)note {
    [OpenKeyManager stopEventTap];
}

- (void)systemDidWake:(NSNotification*)note {
    [self startTypingWhenPermitted];
}

- (void)activeSpaceChanged:(NSNotification*)note {
    if ([OpenKeyManager isInited])
        RequestNewSession();
}

- (void)activeAppChanged:(NSNotification*)note {
    InvalidateSpotlightState();
    if ([OpenKeyManager isInited])
        RequestNewSession();
}

@end
