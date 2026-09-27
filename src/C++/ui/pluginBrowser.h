#pragma once

#import <AppKit/AppKit.h>

@class KineticPluginBrowser;

@protocol KineticPluginBrowserDelegate <NSObject>
- (void)pluginBrowserDidRequestRefresh:(KineticPluginBrowser*)browser;
- (void)pluginBrowser:(KineticPluginBrowser*)browser
    didRequestAction:(NSString*)action
           forPlugin:(NSDictionary<NSString*, id>*)plugin;
@end

@interface KineticPluginBrowser : NSView
@property(nonatomic, assign) id<KineticPluginBrowserDelegate> delegate;
@property(nonatomic, copy) NSArray<NSDictionary<NSString*, id>*>* plugins;
@property(nonatomic, copy) NSString* status;
@end
