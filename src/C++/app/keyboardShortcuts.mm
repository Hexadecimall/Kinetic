#import "keyboardShortcuts.h"

namespace {

NSEventModifierFlags normalizedModifiers(NSEvent* event) {
    constexpr NSEventModifierFlags shortcutModifiers =
        NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl |
        NSEventModifierFlagShift | NSEventModifierFlagFunction;
    return event.modifierFlags & shortcutModifiers;
}

BOOL matches(NSEvent* event, NSString* key, NSEventModifierFlags modifiers) {
    NSString* pressed = event.charactersIgnoringModifiers.lowercaseString;
    return [pressed isEqualToString:key] && normalizedModifiers(event) == modifiers;
}

} // namespace

KineticShortcutCommand kineticShortcutCommandForEvent(NSEvent* event) {
    if (event.type != NSEventTypeKeyDown || event.isARepeat) {
        return KineticShortcutCommandNone;
    }

    if (matches(event, @"n", NSEventModifierFlagCommand)) {
        return KineticShortcutCommandNewTextFile;
    }
    if (matches(event, @"o", NSEventModifierFlagCommand)) {
        return KineticShortcutCommandOpenFile;
    }
    if (matches(event, @"s", NSEventModifierFlagCommand)) {
        return KineticShortcutCommandSaveFile;
    }
    if (matches(event, @"[", NSEventModifierFlagCommand | NSEventModifierFlagShift)) {
        return KineticShortcutCommandPreviousTab;
    }
    if (matches(event, @"]", NSEventModifierFlagCommand | NSEventModifierFlagShift)) {
        return KineticShortcutCommandNextTab;
    }
    if (matches(event, @"q", NSEventModifierFlagCommand)) {
        return KineticShortcutCommandQuit;
    }
    if (matches(event, @"w", NSEventModifierFlagCommand)) {
        return KineticShortcutCommandCloseWindow;
    }
    if (matches(event, @"m", NSEventModifierFlagCommand)) {
        return KineticShortcutCommandMinimizeWindow;
    }
    if (matches(event, @"h", NSEventModifierFlagCommand)) {
        return KineticShortcutCommandHideApplication;
    }
    if (matches(event, @"f", NSEventModifierFlagFunction)) {
        return KineticShortcutCommandToggleFullScreen;
    }

    return KineticShortcutCommandNone;
}
