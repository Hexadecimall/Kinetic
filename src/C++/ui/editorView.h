#pragma once

#import "kineticCommands.h"
#import <AppKit/AppKit.h>

@interface KineticEditorView : NSView
@property(nonatomic, assign) id<KineticCommandHandler> commandHandler;
- (instancetype)initWithFrame:(NSRect)frameRect
                     contents:(NSString*)contents
                      fileUrl:(NSURL*)fileUrl;
@property(nonatomic, readonly, copy) NSString* documentText;
@property(nonatomic, strong) NSURL* fileUrl;
@property(nonatomic, strong) NSURL* workspaceUrl;
@property(nonatomic, copy) NSString* documentTitle;
@property(nonatomic, copy) NSArray<NSString*>* tabTitles;
@property(nonatomic, copy) NSIndexSet* dirtyTabIndexes;
@property(nonatomic) NSUInteger activeTabIndex;
@property(nonatomic, readonly) BOOL dirty;
- (void)markSaved;
@end
