#pragma once

#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, KineticFileDialogMode) {
    KineticFileDialogModeOpen = 0,
    KineticFileDialogModeOpenFolder,
    KineticFileDialogModeSave,
};

@class KineticFileDialog;

@protocol KineticFileDialogDelegate <NSObject>
- (void)fileDialog:(KineticFileDialog*)dialog
     didChoosePath:(NSString*)path
              mode:(KineticFileDialogMode)mode;
- (void)fileDialogDidCancel:(KineticFileDialog*)dialog;
@end

@interface KineticFileDialog : NSView
- (instancetype)initWithFrame:(NSRect)frameRect
                         mode:(KineticFileDialogMode)mode
                  initialPath:(NSString*)initialPath
                     delegate:(id<KineticFileDialogDelegate>)delegate;
- (void)showError:(NSString*)message;
@end
