#import <AppKit/AppKit.h>
#import <MetalKit/MetalKit.h>

#include "editorView.h"
#include "fileDialog.h"
#include "homeView.h"
#include "keyboardShortcuts.h"
#include "kineticBackend.h"
#include "kineticCommands.h"
#include "trafficBar.h"
#include "tween.h"

@interface KineticApplication : NSApplication
@end

@implementation KineticApplication

- (void)sendEvent:(NSEvent*)event {
    NSWindow* window = self.keyWindow ?: self.mainWindow;
    switch (kineticShortcutCommandForEvent(event)) {
    case KineticShortcutCommandNewTextFile:
        [(id<KineticCommandHandler>)self.delegate newTextFile];
        return;
    case KineticShortcutCommandOpenFile:
        [(id<KineticCommandHandler>)self.delegate openFile];
        return;
    case KineticShortcutCommandSaveFile:
        [(id<KineticCommandHandler>)self.delegate saveFile];
        return;
    case KineticShortcutCommandQuit:
        [self terminate:nil];
        return;
    case KineticShortcutCommandCloseWindow:
        if (![(id<KineticCommandHandler>)self.delegate closeActiveTab]) {
            [window performClose:nil];
        }
        return;
    case KineticShortcutCommandMinimizeWindow:
        [window performMiniaturize:nil];
        return;
    case KineticShortcutCommandHideApplication:
        [self hide:nil];
        return;
    case KineticShortcutCommandToggleFullScreen:
        [window toggleFullScreen:nil];
        return;
    case KineticShortcutCommandNone:
        break;
    }

    [super sendEvent:event];
}

@end

@interface KineticSurface : MTKView <MTKViewDelegate>
@property(nonatomic, strong) id<MTLCommandQueue> commandQueue;
@end

@implementation KineticSurface

- (instancetype)initWithFrame:(NSRect)frameRect device:(id<MTLDevice>)device {
    self = [super initWithFrame:frameRect device:device];
    if (self) {
        self.delegate = self;
        self.commandQueue = [device newCommandQueue];
        self.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
        self.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
        self.wantsLayer = YES;
        self.layer.opaque = NO;
        self.enableSetNeedsDisplay = YES;
        self.paused = YES;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    }
    return self;
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {
    (void)view;
    (void)size;
}

- (void)drawInMTKView:(MTKView*)view {
    MTLRenderPassDescriptor* pass = view.currentRenderPassDescriptor;
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (pass == nil || drawable == nil) {
        return;
    }

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

@end

@interface KineticApplicationDelegate
    : NSObject <NSApplicationDelegate, KineticCommandHandler, KineticFileDialogDelegate>
@property(nonatomic, strong) NSWindow* window;
@property(nonatomic, strong) NSView* content;
@property(nonatomic, strong) KineticHomeView* home;
@property(nonatomic, strong) KineticTrafficBar* trafficBar;
@property(nonatomic, strong) KineticEditorView* editor;
@property(nonatomic, strong) KineticFileDialog* fileDialog;
@property(nonatomic, strong) NSURL* workspaceUrl;
@end

@implementation KineticApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    (void)notification;

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) {
        [NSApp terminate:nil];
        return;
    }

    NSRect frame = NSMakeRect(0, 0, 1180, 760);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
                              NSWindowStyleMaskFullSizeContentView;

    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = [NSString stringWithFormat:@"Kinetic %s", kineticBackendVersion()];
    self.window.titlebarAppearsTransparent = YES;
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    self.window.opaque = NO;
    self.window.backgroundColor = NSColor.clearColor;
    self.window.hasShadow = YES;
    self.window.minSize = NSMakeSize(720, 480);

    [self.window standardWindowButton:NSWindowCloseButton].hidden = YES;
    [self.window standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
    [self.window standardWindowButton:NSWindowZoomButton].hidden = YES;

    self.content = [[NSView alloc] initWithFrame:frame];
    NSVisualEffectView* backdrop = [[NSVisualEffectView alloc] initWithFrame:self.content.bounds];
    backdrop.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    backdrop.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    backdrop.material = NSVisualEffectMaterialUnderWindowBackground;
    backdrop.state = NSVisualEffectStateActive;
    KineticSurface* surface = [[KineticSurface alloc] initWithFrame:self.content.bounds
                                                             device:device];
    self.home = [[KineticHomeView alloc] initWithFrame:self.content.bounds];
    self.home.commandHandler = self;
    const CGFloat trafficBarHeight = [KineticTrafficBar preferredHeight];
    self.trafficBar = [[KineticTrafficBar alloc]
        initWithFrame:NSMakeRect(0.0, NSHeight(self.content.bounds) - trafficBarHeight,
                                 NSWidth(self.content.bounds), trafficBarHeight)];
    self.trafficBar.commandHandler = self;
    [self.content addSubview:backdrop];
    [self.content addSubview:surface];
    [self.content addSubview:self.home];
    [self.content addSubview:self.trafficBar];
    self.window.contentView = self.content;
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)openEditorWithContents:(NSString*)contents fileUrl:(NSURL*)fileUrl {
    KineticEditorView* previousEditor = self.editor;
    self.editor = [[KineticEditorView alloc] initWithFrame:self.content.bounds
                                                  contents:contents
                                                   fileUrl:fileUrl];
    self.editor.commandHandler = self;
    self.editor.workspaceUrl = self.workspaceUrl;
    NSRect finalFrame = self.content.bounds;
    self.editor.frame = NSOffsetRect(finalFrame, 0.0, -8.0);
    self.editor.alphaValue = 0.0;
    [self.content addSubview:self.editor positioned:NSWindowBelow relativeTo:self.trafficBar];
    [KineticTween animateView:self.editor
                      toFrame:finalFrame
                      toAlpha:1.0
                     duration:0.18
                   completion:nil];

    if (!self.home.hidden) {
        [KineticTween animateView:self.home
                          toFrame:self.home.frame
                          toAlpha:0.0
                         duration:0.12
                       completion:^{
                         self.home.hidden = YES;
                         self.home.alphaValue = 1.0;
                       }];
    }
    if (previousEditor != nil) {
        [KineticTween animateView:previousEditor
                          toFrame:NSOffsetRect(previousEditor.frame, 0.0, 5.0)
                          toAlpha:0.0
                         duration:0.12
                       completion:^{
                         [previousEditor removeFromSuperview];
                       }];
    }
    [self.window makeFirstResponder:self.editor];
}

- (void)newTextFile {
    [self openEditorWithContents:@"" fileUrl:nil];
}

- (void)openFile {
    [self presentFileDialogWithMode:KineticFileDialogModeOpen initialPath:@"~/"];
}

- (void)openFileAtUrl:(NSURL*)fileUrl {
    NSError* error = nil;
    NSString* contents = [NSString stringWithContentsOfURL:fileUrl
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (contents != nil) {
        [self openEditorWithContents:contents fileUrl:fileUrl];
    }
}

- (void)openFolder {
    [self presentFileDialogWithMode:KineticFileDialogModeOpenFolder initialPath:@"~/"];
}

- (BOOL)writeEditorToUrl:(NSURL*)fileUrl {
    NSError* error = nil;
    if (![self.editor.documentText writeToURL:fileUrl
                                   atomically:YES
                                     encoding:NSUTF8StringEncoding
                                        error:&error]) {
        return NO;
    }
    self.editor.fileUrl = fileUrl;
    [self.editor markSaved];
    return YES;
}

- (void)saveFile {
    if (self.editor == nil) {
        return;
    }
    if (self.editor.fileUrl != nil) {
        [self writeEditorToUrl:self.editor.fileUrl];
        return;
    }

    [self presentFileDialogWithMode:KineticFileDialogModeSave initialPath:@"~/Untitled.txt"];
}

- (void)presentFileDialogWithMode:(KineticFileDialogMode)mode initialPath:(NSString*)initialPath {
    [self.fileDialog removeFromSuperview];
    self.fileDialog = [[KineticFileDialog alloc] initWithFrame:self.content.bounds
                                                          mode:mode
                                                   initialPath:initialPath
                                                      delegate:self];
    self.fileDialog.alphaValue = 0.0;
    [self.content addSubview:self.fileDialog positioned:NSWindowAbove relativeTo:nil];
    [KineticTween animateView:self.fileDialog
                      toFrame:self.content.bounds
                      toAlpha:1.0
                     duration:0.14
                   completion:nil];
    [self.window makeFirstResponder:self.fileDialog];
}

- (void)dismissFileDialog {
    KineticFileDialog* closingDialog = self.fileDialog;
    self.fileDialog = nil;
    [KineticTween animateView:closingDialog
                      toFrame:closingDialog.frame
                      toAlpha:0.0
                     duration:0.1
                   completion:^{
                     [closingDialog removeFromSuperview];
                   }];
    [self.window makeFirstResponder:self.editor ?: self.home];
}

- (void)fileDialog:(KineticFileDialog*)dialog
     didChoosePath:(NSString*)path
              mode:(KineticFileDialogMode)mode {
    NSURL* fileUrl = [NSURL fileURLWithPath:path];
    if (mode == KineticFileDialogModeOpenFolder) {
        BOOL isDirectory = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] ||
            !isDirectory) {
            [dialog showError:@"That folder does not exist."];
            return;
        }
        self.workspaceUrl = fileUrl;
        [self dismissFileDialog];
        if (self.editor == nil) {
            [self openEditorWithContents:@"" fileUrl:nil];
        } else {
            self.editor.workspaceUrl = fileUrl;
        }
        return;
    }
    if (mode == KineticFileDialogModeOpen) {
        BOOL isDirectory = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] ||
            isDirectory) {
            [dialog showError:@"That file does not exist."];
            return;
        }
        NSError* error = nil;
        NSString* contents = [NSString stringWithContentsOfURL:fileUrl
                                                      encoding:NSUTF8StringEncoding
                                                         error:&error];
        if (contents == nil) {
            [dialog showError:@"Kinetic could not read this UTF-8 file."];
            return;
        }
        [self dismissFileDialog];
        [self openEditorWithContents:contents fileUrl:fileUrl];
        return;
    }

    NSString* parent = path.stringByDeletingLastPathComponent;
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:parent isDirectory:&isDirectory] ||
        !isDirectory) {
        [dialog showError:@"The destination folder does not exist."];
        return;
    }
    if (![self writeEditorToUrl:fileUrl]) {
        [dialog showError:@"Kinetic could not save to this location."];
        return;
    }
    [self dismissFileDialog];
}

- (void)fileDialogDidCancel:(KineticFileDialog*)dialog {
    if (dialog == self.fileDialog) {
        [self dismissFileDialog];
    }
}

- (BOOL)closeActiveTab {
    if (self.editor == nil) {
        return NO;
    }

    KineticEditorView* closingEditor = self.editor;
    self.editor = nil;
    self.home.hidden = NO;
    self.home.alphaValue = 0.0;
    NSRect homeFrame = self.home.frame;
    self.home.frame = NSOffsetRect(homeFrame, 0.0, 6.0);
    [KineticTween animateView:self.home toFrame:homeFrame toAlpha:1.0 duration:0.18 completion:nil];
    [KineticTween animateView:closingEditor
                      toFrame:NSOffsetRect(closingEditor.frame, 0.0, -6.0)
                      toAlpha:0.0
                     duration:0.14
                   completion:^{
                     [closingEditor removeFromSuperview];
                   }];
    [self.window makeFirstResponder:self.home];
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    (void)sender;
    return YES;
}

@end

int main(int argc, const char* argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        KineticApplication* application = [KineticApplication sharedApplication];
        KineticApplicationDelegate* delegate = [[KineticApplicationDelegate alloc] init];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }

    return 0;
}
