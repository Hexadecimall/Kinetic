#pragma once

#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, KineticActivitySection) {
    KineticActivitySectionNone = -1,
    KineticActivitySectionExplorer = 0,
    KineticActivitySectionSourceControl,
    KineticActivitySectionPlugins,
    KineticActivitySectionSettings,
};

@class KineticActivityBar;

@protocol KineticActivityBarDelegate <NSObject>
- (void)activityBarDidRequestOpenFile:(KineticActivityBar*)activityBar;
- (void)activityBarDidRequestOpenFolder:(KineticActivityBar*)activityBar;
- (void)activityBarDidRequestCreateFolder:(KineticActivityBar*)activityBar;
- (void)activityBar:(KineticActivityBar*)activityBar didRequestCreateFileInDirectory:(NSURL*)url;
- (void)activityBar:(KineticActivityBar*)activityBar didRequestCreateFolderInDirectory:(NSURL*)url;
- (void)activityBarDidRequestSaveFile:(KineticActivityBar*)activityBar;
- (void)activityBarDidRequestCloseTab:(KineticActivityBar*)activityBar;
- (void)activityBar:(KineticActivityBar*)activityBar didRequestOpenUrl:(NSURL*)url;
- (void)activityBar:(KineticActivityBar*)activityBar
    didActivateSection:(KineticActivitySection)section;
- (void)activityBar:(KineticActivityBar*)activityBar didRequestPluginCommand:(NSString*)commandId;
@end

@interface KineticActivityBar : NSView
@property(nonatomic, assign) id<KineticActivityBarDelegate> delegate;
@property(nonatomic, copy) NSString* documentTitle;
@property(nonatomic, strong) NSURL* workspaceUrl;
@property(nonatomic, copy) NSArray<NSString*>* pluginNames;
@property(nonatomic, copy) NSArray<NSDictionary<NSString*, NSString*>*>* pluginCommands;
@property(nonatomic, copy) NSString* pluginConfigurationError;
@property(nonatomic, readonly) KineticActivitySection activeSection;
@property(nonatomic, readonly, copy) NSDictionary* workspaceUiState;
+ (CGFloat)railWidth;
- (void)applyWorkspaceUiState:(NSDictionary*)state;
- (void)revealCreatedFolderAtUrl:(NSURL*)url;
- (void)revealCreatedFileAtUrl:(NSURL*)url;
- (void)activateSection:(KineticActivitySection)section animated:(BOOL)animated;
- (void)deactivateSection;
@end
