#pragma once

#import <AppKit/AppKit.h>

NSRect kineticVisibleWindowFrame(NSRect frame, NSArray<NSValue*>* screens, NSSize minimumSize);

@interface KineticWindowState : NSObject <NSWindowDelegate>
- (instancetype)initWithWindow:(NSWindow*)window;
- (BOOL)restore;
- (void)save;
@end
