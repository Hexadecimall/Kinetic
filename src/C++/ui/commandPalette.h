#pragma once

#import <AppKit/AppKit.h>

@class KineticCommandPalette;

@protocol KineticCommandPaletteDelegate <NSObject>
- (void)commandPaletteDidClose:(KineticCommandPalette*)palette;
- (void)commandPalette:(KineticCommandPalette*)palette didChooseCommand:(NSString*)commandId;
@end

@interface KineticCommandPalette : NSView
@property(nonatomic, assign) id<KineticCommandPaletteDelegate> delegate;
@property(nonatomic, copy) NSArray<NSDictionary<NSString*, NSString*>*>* commands;
- (void)focusQuery;
@end
