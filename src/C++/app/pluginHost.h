#pragma once

#import <Foundation/Foundation.h>

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
@end

@interface KineticPluginHost : NSObject
@property(nonatomic, assign) id<KineticPluginHostDelegate> delegate;
@property(nonatomic, readonly, copy) NSArray<NSString*>* loadedPluginNames;
@property(nonatomic, readonly, copy) NSArray<NSDictionary<NSString*, NSString*>*>* commands;
@property(nonatomic, readonly, copy) NSString* configurationError;
+ (NSURL*)userPluginRootUrl;
- (void)loadPluginsAtUrl:(NSURL*)directoryUrl configurationUrl:(NSURL*)configurationUrl;
- (BOOL)executeCommand:(NSString*)commandId;
- (void)emitEvent:(NSString*)eventName;
@end
