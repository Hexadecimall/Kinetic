#pragma once

#import <AppKit/AppKit.h>

@class KineticCloneDialog;

@protocol KineticCloneDialogDelegate <NSObject>
- (void)cloneDialogDidCancel:(KineticCloneDialog*)dialog;
- (void)cloneDialog:(KineticCloneDialog*)dialog didRequestDestinationForUrl:(NSString*)url;
@end

@interface KineticCloneDialog : NSView
@property(nonatomic, assign) id<KineticCloneDialogDelegate> delegate;
@property(nonatomic, copy) NSString* repositoryUrl;
@property(nonatomic, copy) NSString* status;
@property(nonatomic) BOOL busy;
- (void)focusUrl;
@end
