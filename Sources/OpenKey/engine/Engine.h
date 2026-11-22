//
//  Engine.h
//  OpenKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//
//  Telex typing engine with Unicode output.
//

#ifndef Engine_h
#define Engine_h

#include "DataType.h"
#include "Vietnamese.h"

/*
 * Switch shortcut (vSwitchKeyStatus)
 * first 8 bit: keycode
 * bit 8: Control, bit 9: Option, bit 10: Command, bit 11: Shift
 * bit 15: beep when switching
 */
#define GET_SWITCH_KEY(data) (data & 0xFF)
#define HAS_CONTROL(data) ((data & 0x100) ? 1 : 0)
#define HAS_OPTION(data) ((data & 0x200) ? 1 : 0)
#define HAS_COMMAND(data) ((data & 0x400) ? 1 : 0)
#define HAS_SHIFT(data) ((data & 0x800) ? 1 : 0)
#define GET_BOOL(data) (data ? 1 : 0)
#define HAS_BEEP(data) (data & 0x8000)

//Settings, defined by the application

/*
 * 0: English
 * 1: Vietnamese
 */
extern int vLanguage;

/*
 * Shortcut that switches between Vietnamese and English (layout above)
 */
extern int vSwitchKeyStatus;

/*
 * 0: òa, úy
 * 1: oà, uý
 */
extern int vUseModernOrthography;

/*
 * 1: an invalid Vietnamese word is turned back into the keys that were typed
 *    (e.g. "windows" stays "windows" instead of "ưindows")
 */
extern int vRestoreIfWrongSpelling;

/**
 * Call this function first to receive data pointer
 */
void* vKeyInit();

/**
 * Convert engine character to real character
 */
Uint32 getCharacterCode(const Uint32& data);

/**
 * MAIN entry point for each key
 * event: mouse or keyboard event
 * state: additional state for event
 * data: key code
 * capsStatus: 1 = shift, 2 = caps lock
 * otherControlKey: ctrl, option,... is pressing
 */
void vKeyHandleEvent(const vKeyEvent& event,
                     const vKeyEventState& state,
                     const Uint16& data,
                     const Uint8& capsStatus=0,
                     const bool& otherControlKey=false);

/**
 * Start a new word
 */
void startNewSession();

#endif /* Engine_h */
