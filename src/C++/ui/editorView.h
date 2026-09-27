#pragma once

#import "activityBar.h"
#import "kineticCommands.h"
#import "searchPopover.h"
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
@property(nonatomic, readonly) KineticActivitySection activeActivitySection;
@property(nonatomic, readonly, copy) NSDictionary* workspaceUiState;
@property(nonatomic, readonly, copy) NSDictionary* searchUiState;
@property(nonatomic, readonly) KineticSearchScope searchScope;
@property(nonatomic, readonly) BOOL searchOpen;
- (void)applyWorkspaceUiState:(NSDictionary*)state;
- (void)applySearchUiState:(NSDictionary*)state;
- (void)applySearchResults:(NSArray<NSDictionary*>*)results
                   loading:(BOOL)loading
                 truncated:(BOOL)truncated;
- (void)focusWorkspaceSearch;
- (void)focusFileSearch;
- (void)toggleFileSearch;
- (void)focusSearchQuery;
- (void)revealLine:(NSUInteger)line column:(NSUInteger)column length:(NSUInteger)length;
- (void)revealCreatedFolderAtUrl:(NSURL*)url;
- (void)revealCreatedFileAtUrl:(NSURL*)url;
- (void)setActivitySection:(KineticActivitySection)section animated:(BOOL)animated;
- (void)markSaved;
- (BOOL)setPluginNumber:(double)value property:(NSString*)property;
- (BOOL)getPluginNumber:(double*)value property:(NSString*)property;
- (void)replaceSelectionFromPlugin:(NSString*)text;
- (void)setPluginNames:(NSArray<NSString*>*)names
              commands:(NSArray<NSDictionary<NSString*, NSString*>*>*)commands
    configurationError:(NSString*)configurationError;
@end
