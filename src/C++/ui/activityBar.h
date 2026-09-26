#pragma once

#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, KineticActivitySection) {
    KineticActivitySectionNone = -1,
    KineticActivitySectionExplorer = 0,
    KineticActivitySectionSearch,
    KineticActivitySectionSourceControl,
    KineticActivitySectionPlugins,
    KineticActivitySectionSettings,
};

@class KineticActivityBar;

@protocol KineticActivityBarDelegate <NSObject>
- (void)activityBarDidRequestOpenFile:(KineticActivityBar*)activityBar;
- (void)activityBarDidRequestOpenFolder:(KineticActivityBar*)activityBar;
- (void)activityBar:(KineticActivityBar*)activityBar didRequestOpenUrl:(NSURL*)url;
- (void)activityBar:(KineticActivityBar*)activityBar
    didActivateSection:(KineticActivitySection)section;
@end

@interface KineticActivityBar : NSView
@property(nonatomic, assign) id<KineticActivityBarDelegate> delegate;
@property(nonatomic, copy) NSString* documentTitle;
@property(nonatomic, strong) NSURL* workspaceUrl;
@property(nonatomic, readonly) KineticActivitySection activeSection;
+ (CGFloat)railWidth;
- (void)deactivateSection;
@end
