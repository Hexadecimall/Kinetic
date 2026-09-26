#pragma once

#import "kineticCommands.h"
#import <AppKit/AppKit.h>

@interface KineticHomeView : NSView
@property(nonatomic, assign) id<KineticCommandHandler> commandHandler;
@end
