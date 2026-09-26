#pragma once

#import "kineticCommands.h"
#import <AppKit/AppKit.h>

@interface KineticHomeView : NSView
@property(nonatomic, assign) id<KineticCommandHandler> commandHandler;
@property(nonatomic, copy) NSArray<NSURL*>* recentProjects;
@end
