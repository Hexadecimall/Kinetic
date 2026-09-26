#pragma once

#import "kineticCommands.h"
#import <AppKit/AppKit.h>

@interface KineticTrafficBar : NSView
@property(nonatomic, assign) id<KineticCommandHandler> commandHandler;
@property(nonatomic) BOOL showsSearch;
@property(nonatomic) BOOL searchActive;
+ (CGFloat)preferredHeight;
@end
