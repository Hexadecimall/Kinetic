#pragma once

#import <AppKit/AppKit.h>

@class KineticPluginHost;

@protocol KineticPluginHostDelegate <NSObject>
- (BOOL)pluginHost:(KineticPluginHost*)host setNumber:(double)value property:(NSString*)property;
- (BOOL)pluginHost:(KineticPluginHost*)host getNumber:(double*)value property:(NSString*)property;
- (BOOL)pluginHost:(KineticPluginHost*)host setString:(NSString*)value property:(NSString*)property;
- (NSString*)pluginHost:(KineticPluginHost*)host getString:(NSString*)property;
- (NSString*)pluginHostActiveDocument:(KineticPluginHost*)host;
- (BOOL)pluginHost:(KineticPluginHost*)host replaceSelection:(NSString*)text;
- (BOOL)pluginHost:(KineticPluginHost*)host getSelection:(NSRange*)selection;
- (BOOL)pluginHost:(KineticPluginHost*)host setSelection:(NSRange)selection;
- (BOOL)pluginHost:(KineticPluginHost*)host replaceRange:(NSRange)range withString:(NSString*)text;
@optional
- (NSString*)pluginHostActiveFilePath:(KineticPluginHost*)host;
- (NSString*)pluginHostWorkspacePath:(KineticPluginHost*)host;
- (void)pluginHost:(KineticPluginHost*)host
    publishDiagnostics:(NSArray<NSDictionary<NSString*, id>*>*)diagnostics
               forPath:(NSString*)path;
- (void)pluginHost:(KineticPluginHost*)host
    openLocationAtPath:(NSString*)path
                  line:(NSUInteger)line
                column:(NSUInteger)column;
- (void)pluginHostContributionsDidChange:(KineticPluginHost*)host;
@end

@interface KineticPluginHost : NSObject
@property(nonatomic, assign) id<KineticPluginHostDelegate> delegate;
@property(nonatomic, readonly, copy) NSArray<NSString*>* loadedPluginNames;
@property(nonatomic, readonly, copy) NSArray<NSDictionary<NSString*, NSString*>*>* commands;
@property(nonatomic, readonly, copy) NSArray<NSDictionary<NSString*, NSString*>*>* fileMenuItems;
@property(nonatomic, readonly, copy) NSArray<NSDictionary<NSString*, id>*>* panels;
@property(nonatomic, readonly, copy) NSString* configurationError;
+ (NSURL*)userPluginRootUrl;
- (void)loadPluginsAtUrl:(NSURL*)directoryUrl configurationUrl:(NSURL*)configurationUrl;
- (BOOL)executeCommand:(NSString*)commandId;
- (BOOL)executeShortcutKey:(NSString*)key modifiers:(uint32_t)modifiers;
- (BOOL)hasFormatterForFileName:(NSString*)fileName;
- (NSString*)formatDocument:(NSString*)text fileName:(NSString*)fileName;
- (void)drawOverlaysInRect:(NSRect)rect;
- (NSArray<NSArray<NSDictionary<NSString*, id>*>*>*)syntaxTokensForLines:(NSArray<NSString*>*)lines
                                                                fileName:(NSString*)fileName;
- (NSArray<NSDictionary<NSString*, NSString*>*>*)completionItemsForPrefix:(NSString*)prefix
                                                                 fileName:(NSString*)fileName;
- (void)emitEvent:(NSString*)eventName;
@end
