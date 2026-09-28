#pragma once

#import <AppKit/AppKit.h>

NSColor* kineticThemeColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha);
NSString* kineticThemeName(void);
void kineticSetThemeName(NSString* name);
NSDictionary<NSString*, NSColor*>* kineticReadThemePalette(NSData* data);
void kineticRefreshThemeInView(NSView* view);
