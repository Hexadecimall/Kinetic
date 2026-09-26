#pragma once

#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, KineticSearchScope) {
    KineticSearchScopeFile = 0,
    KineticSearchScopeProject,
};

@class KineticSearchPopover;

@protocol KineticSearchPopoverDelegate <NSObject>
- (void)searchPopoverDidChange:(KineticSearchPopover*)popover;
- (void)searchPopover:(KineticSearchPopover*)popover didSelectResult:(NSDictionary*)result;
- (void)searchPopoverDidRequestClose:(KineticSearchPopover*)popover;
@end

@interface KineticSearchPopover : NSView
@property(nonatomic, assign) id<KineticSearchPopoverDelegate> delegate;
@property(nonatomic, readonly, copy) NSString* query;
@property(nonatomic, readonly) KineticSearchScope scope;
@property(nonatomic, readonly) BOOL matchCase;
@property(nonatomic) BOOL projectAvailable;
@property(nonatomic, readonly, copy) NSArray<NSDictionary*>* results;
@property(nonatomic, readonly, copy) NSDictionary* searchState;
- (void)applySearchState:(NSDictionary*)state;
- (void)selectScope:(KineticSearchScope)scope;
- (void)applyResults:(NSArray<NSDictionary*>*)results
             loading:(BOOL)loading
           truncated:(BOOL)truncated;
- (void)focusQuery;
- (CGFloat)preferredHeight;
@end
