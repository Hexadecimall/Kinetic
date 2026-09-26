#pragma once

#import "kineticCommands.h"
#import <AppKit/AppKit.h>

@interface KineticTrafficBar : NSView
@property(nonatomic, assign) id<KineticCommandHandler> commandHandler;
+ (CGFloat)preferredHeight;
@end
