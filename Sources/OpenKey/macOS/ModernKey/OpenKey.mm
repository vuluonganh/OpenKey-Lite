//
//  OpenKey.mm
//  OpenKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//
//  Event tap callback: feeds key presses to the engine and sends the
//  engine's result back as backspaces + Unicode text.
//
#import <Cocoa/Cocoa.h>
#import "Engine.h"
#import "AppDelegate.h"
#import "OpenKeyManager.h"

#define FRONT_APP [[NSWorkspace sharedWorkspace] frontmostApplication].bundleIdentifier
#define OTHER_CONTROL_KEY (_flag & kCGEventFlagMaskCommand) || (_flag & kCGEventFlagMaskControl) || \
                            (_flag & kCGEventFlagMaskAlternate) || (_flag & kCGEventFlagMaskSecondaryFn) || \
                            (_flag & kCGEventFlagMaskNumericPad) || (_flag & kCGEventFlagMaskHelp)
#define MAX_UNICODE_STRING  20

extern "C" {
    //apps that need a different invisible character for the autocomplete fix
    static NSArray* _niceSpaceApp = @[@"com.sublimetext.3", @"com.sublimetext.2"];
    //apps where text is replaced by selecting it instead of sending backspaces
    static NSArray* _selectionReplacementApp = @[@"com.apple.Spotlight"];

    static CGEventSourceRef myEventSource = NULL;
    static vKeyHookState* pData;
    static CGEventRef eventBackSpaceDown;
    static CGEventRef eventBackSpaceUp;
    static CGKeyCode _keycode;
    static CGEventFlags _flag, _lastFlag = 0;
    static CGEventTapProxy _proxy;
    static Uint16 _newCharString[MAX_UNICODE_STRING];
    static bool _hasJustUsedHotKey = false;

    void OpenKeyInit() {
        myEventSource = CGEventSourceCreate(kCGEventSourceStatePrivate);
        pData = (vKeyHookState*)vKeyInit();
        eventBackSpaceDown = CGEventCreateKeyboardEvent(myEventSource, KEY_DELETE, true);
        eventBackSpaceUp = CGEventCreateKeyboardEvent(myEventSource, KEY_DELETE, false);
    }

    void RequestNewSession() {
        vKeyHandleEvent(vKeyEvent::Mouse, vKeyEventState::MouseDown, 0);
    }

    // Spotlight's search field never becomes the frontmost app, so the only way to see it
    // is to list on-screen windows, which is expensive. Cache the answer and list windows
    // again only after an event that can open or close Spotlight (see InvalidateSpotlightState)
    // or once the cached answer is older than SPOTLIGHT_CACHE_SECONDS.
    #define SPOTLIGHT_CACHE_SECONDS 1.0
    static BOOL _spotlightVisible = NO;
    static BOOL _spotlightStateDirty = YES;
    static CFAbsoluteTime _spotlightCheckedAt = 0;

    void InvalidateSpotlightState() {
        _spotlightStateDirty = YES;
    }

    static BOOL isSpotlightVisible() {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (!_spotlightStateDirty && now - _spotlightCheckedAt < SPOTLIGHT_CACHE_SECONDS) {
            return _spotlightVisible;
        }
        _spotlightVisible = NO;
        NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
                                                                        kCGNullWindowID));
        for (NSDictionary *window in windows) {
            if ([[window objectForKey:(__bridge NSString *)kCGWindowOwnerName] isEqualToString:@"Spotlight"]) {
                _spotlightVisible = YES;
                break;
            }
        }
        _spotlightStateDirty = NO;
        _spotlightCheckedAt = now;
        return _spotlightVisible;
    }

    //browsers and Excel autocomplete the word being typed; an invisible character
    //before the backspaces stops the autocomplete from eating the edit
    static BOOL shouldUseAutocompleteFix(NSString* topApp) {
        if (isSpotlightVisible()) return NO;
        if (topApp == nil) return YES;
        return ![_selectionReplacementApp containsObject:topApp];
    }

    static BOOL shouldUseSelectionReplacement(NSString* topApp) {
        return isSpotlightVisible() || [_selectionReplacementApp containsObject:topApp];
    }

    static void PostKeyEvents(CGEventRef down, CGEventRef up) {
        CGEventTapPostEvent(_proxy, down);
        CGEventTapPostEvent(_proxy, up);
        CFRelease(down);
        CFRelease(up);
    }

    static void SendUnicodeString(const UniChar* chars, UniCharCount length) {
        CGEventRef down = CGEventCreateKeyboardEvent(myEventSource, 0, true);
        CGEventRef up = CGEventCreateKeyboardEvent(myEventSource, 0, false);
        CGEventKeyboardSetUnicodeString(down, length, chars);
        CGEventKeyboardSetUnicodeString(up, length, chars);
        PostKeyEvents(down, up);
    }

    static void SendKeyCode(Uint32 data) {
        UniChar ch = (Uint16)data;
        if (data & CHAR_CODE_MASK) { //unicode character
            SendUnicodeString(&ch, 1);
            return;
        }
        CGEventRef down = CGEventCreateKeyboardEvent(myEventSource, ch, true);
        CGEventRef up = CGEventCreateKeyboardEvent(myEventSource, ch, false);
        CGEventFlags flags = CGEventGetFlags(down);
        if (data & CAPS_MASK) {
            flags |= kCGEventFlagMaskShift;
        } else {
            flags &= ~kCGEventFlagMaskShift;
        }
        flags |= kCGEventFlagMaskNonCoalesced;
        CGEventSetFlags(down, flags);
        CGEventSetFlags(up, flags);
        PostKeyEvents(down, up);
    }

    static void SendEmptyCharacter() {
        UniChar ch = [_niceSpaceApp containsObject:FRONT_APP] ? 0x200C : 0x202F;
        SendUnicodeString(&ch, 1);
    }

    static void SendBackspace() {
        CGEventTapPostEvent(_proxy, eventBackSpaceDown);
        CGEventTapPostEvent(_proxy, eventBackSpaceUp);
    }

    static void SendShiftAndLeftArrow() {
        CGEventRef down = CGEventCreateKeyboardEvent(myEventSource, KEY_LEFT, true);
        CGEventRef up = CGEventCreateKeyboardEvent(myEventSource, KEY_LEFT, false);
        CGEventFlags flags = CGEventGetFlags(down) | kCGEventFlagMaskShift;
        CGEventSetFlags(down, flags);
        CGEventSetFlags(up, flags);
        PostKeyEvents(down, up);
    }

    //send the engine's new characters (at most 16 per event), then the typed key on restore
    static void SendNewCharString(const Uint16& offset=0) {
        int count = 0;
        bool willContinueSending = false;
        bool willSendControlKey = false;
        Uint16 newCharSize = pData->newCharCount;

        for (int k = pData->newCharCount - 1 - offset; k >= 0; k--) {
            if (count >= 16) {
                willContinueSending = true;
                break;
            }
            Uint32 c = pData->charData[k];
            _newCharString[count++] = (c & CHAR_CODE_MASK) ? (Uint16)c : keyCodeToCharacter(c);
        }

        if (!willContinueSending && (pData->code == vRestore || pData->code == vRestoreAndStartNewSession)) {
            if (keyCodeToCharacter(_keycode) != 0) {
                newCharSize++;
                _newCharString[count++] = keyCodeToCharacter(_keycode | ((_flag & kCGEventFlagMaskAlphaShift) || (_flag & kCGEventFlagMaskShift) ? CAPS_MASK : 0));
            } else {
                willSendControlKey = true;
            }
        }
        if (!willContinueSending && pData->code == vRestoreAndStartNewSession) {
            startNewSession();
        }

        SendUnicodeString(_newCharString, willContinueSending ? 16 : newCharSize - offset);

        if (willContinueSending) {
            SendNewCharString(16);
        }

        //the word was invalid and the last key was a control key such as Tab or an arrow
        if (willSendControlKey) {
            SendKeyCode(_keycode);
        }
    }

    static bool checkHotKey(int hotKeyData, bool checkKeyCode=true) {
        if (HAS_CONTROL(hotKeyData) ^ GET_BOOL(_lastFlag & kCGEventFlagMaskControl))
            return false;
        if (HAS_OPTION(hotKeyData) ^ GET_BOOL(_lastFlag & kCGEventFlagMaskAlternate))
            return false;
        if (HAS_COMMAND(hotKeyData) ^ GET_BOOL(_lastFlag & kCGEventFlagMaskCommand))
            return false;
        if (HAS_SHIFT(hotKeyData) ^ GET_BOOL(_lastFlag & kCGEventFlagMaskShift))
            return false;
        if (checkKeyCode && GET_SWITCH_KEY(hotKeyData) != _keycode)
            return false;
        return true;
    }

    static void switchLanguage() {
        if (HAS_BEEP(vSwitchKeyStatus))
            NSBeep();
        [appDelegate setVietnamese:!vLanguage];
    }

    /**
     * MAIN HOOK entry
     */
    CGEventRef OpenKeyCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
        //macOS turns a slow tap off; turn it back on
        if (type == kCGEventTapDisabledByTimeout) {
            [OpenKeyManager reenableEventTap];
            return event;
        }

        //dont handle my event
        if (CGEventGetIntegerValueField(event, kCGEventSourceStateID) == CGEventSourceGetSourceStateID(myEventSource)) {
            return event;
        }

        _flag = CGEventGetFlags(event);
        _keycode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);

        //Spotlight opens with a modifier shortcut and closes with Escape, Return or a click
        if (type == kCGEventFlagsChanged || type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown ||
            (type == kCGEventKeyDown && (_keycode == KEY_ESC || _keycode == KEY_RETURN || _keycode == KEY_ENTER || (OTHER_CONTROL_KEY)))) {
            InvalidateSpotlightState();
        }

        //switch language shortcut: modifiers + key, or modifiers only (released together)
        if (type == kCGEventKeyDown) {
            if (GET_SWITCH_KEY(vSwitchKeyStatus) != _keycode) {
                _lastFlag = 0;
            } else if (checkHotKey(vSwitchKeyStatus, GET_SWITCH_KEY(vSwitchKeyStatus) != 0xFE)) {
                switchLanguage();
                _lastFlag = 0;
                _hasJustUsedHotKey = true;
                return NULL;
            }
            _hasJustUsedHotKey = _lastFlag != 0;
        } else if (type == kCGEventFlagsChanged) {
            if (_lastFlag == 0 || _lastFlag < _flag) {
                _lastFlag = _flag;
            } else if (_lastFlag > _flag) {
                if (checkHotKey(vSwitchKeyStatus, GET_SWITCH_KEY(vSwitchKeyStatus) != 0xFE)) {
                    _lastFlag = 0;
                    switchLanguage();
                    _hasJustUsedHotKey = true;
                    return NULL;
                }
                _lastFlag = 0;
                _hasJustUsedHotKey = false;
            }
        }

        if ((type != kCGEventKeyDown) &&
            (type != kCGEventLeftMouseDown) && (type != kCGEventRightMouseDown))
            return event;

        _proxy = proxy;

        //English mode: pass everything through
        if (vLanguage == 0) {
            return event;
        }

        //a click moves the caret, so the next key starts a new word
        if (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown) {
            RequestNewSession();
            return event;
        }

        //send event signal to Engine
        vKeyHandleEvent(vKeyEvent::Keyboard,
                        vKeyEventState::KeyDown,
                        _keycode,
                        _flag & kCGEventFlagMaskShift ? 1 : (_flag & kCGEventFlagMaskAlphaShift ? 2 : 0),
                        OTHER_CONTROL_KEY);
        if (pData->code == vDoNothing) {
            return event;
        }

        NSString* frontApp = FRONT_APP;
        if (shouldUseAutocompleteFix(frontApp) && pData->extCode != 4) {
            SendEmptyCharacter();
            pData->backspaceCount++;
        }

        if (shouldUseSelectionReplacement(frontApp) && pData->backspaceCount > 0) {
            for (int i = 0; i < pData->backspaceCount; i++) {
                SendShiftAndLeftArrow();
            }
            pData->backspaceCount = 0;
        }

        if (pData->backspaceCount > 0 && pData->backspaceCount < MAX_BUFF) {
            for (int i = 0; i < pData->backspaceCount; i++) {
                SendBackspace();
            }
        }

        SendNewCharString();
        return NULL;
    }
}
