#pragma once

#import "githubAccount.h"
#import "kineticCommands.h"
#import <AppKit/AppKit.h>

@interface KineticTrafficBar : NSView
@property(nonatomic, assign) id<KineticCommandHandler> commandHandler;
@property(nonatomic) BOOL showsSearch;
@property(nonatomic) BOOL searchActive;
@property(nonatomic, strong) KineticGitHubAccount* githubAccount;
- (void)accountDidChange;
+ (CGFloat)preferredHeight;
@end
