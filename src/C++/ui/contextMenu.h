#pragma once

#import <AppKit/AppKit.h>

@interface KineticContextMenu : NSView
+ (void)showInView:(NSView*)view
           atPoint:(NSPoint)point
             items:(NSArray<NSDictionary<NSString*, id>*>*)items
           handler:(void (^)(NSUInteger index))handler;
@end
