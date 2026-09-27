#pragma once

#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, KineticShortcutCommand) {
    KineticShortcutCommandNone = 0,
    KineticShortcutCommandNewTextFile,
    KineticShortcutCommandOpenFile,
    KineticShortcutCommandSaveFile,
    KineticShortcutCommandSearchWorkspace,
    KineticShortcutCommandSearchFile,
    KineticShortcutCommandSettings,
    KineticShortcutCommandPreviousTab,
    KineticShortcutCommandNextTab,
    KineticShortcutCommandQuit,
    KineticShortcutCommandCloseWindow,
    KineticShortcutCommandMinimizeWindow,
    KineticShortcutCommandHideApplication,
    KineticShortcutCommandToggleFullScreen,
};

KineticShortcutCommand kineticShortcutCommandForEvent(NSEvent* event);
