#pragma once
#import <AppKit/AppKit.h>

@interface KineticToolPrompt : NSView
@property(nonatomic, copy) NSString* message;
@property(nonatomic) BOOL busy;
@property(nonatomic, copy) void (^answer)(BOOL install);
@end
