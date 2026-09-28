#pragma once
#import <AppKit/AppKit.h>

@interface KineticUtilityPanel : NSView
@property(nonatomic, copy) void (^closeHandler)(void);
- (instancetype)initWithFrame:(NSRect)frame content:(NSView*)content;
- (void)presentAnimated:(BOOL)animated duration:(NSTimeInterval)duration;
- (void)dismissAnimated:(BOOL)animated duration:(NSTimeInterval)duration;
@end
