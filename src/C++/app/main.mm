#import <AppKit/AppKit.h>
#import <MetalKit/MetalKit.h>
#include <fcntl.h>
#include <unistd.h>

#include "cloneDialog.h"
#include "commandPalette.h"
#include "editorView.h"
#include "fileDialog.h"
#include "githubAccount.h"
#include "homeView.h"
#include "keyboardShortcuts.h"
#include "kinetic/pluginApi.h"
#include "kineticBackend.h"
#include "kineticCommands.h"
#include "pluginHost.h"
#include "theme.h"
#include "toolPrompt.h"
#include "trafficBar.h"
#include "tween.h"
#include "windowState.h"
#include "workspaceSearch.h"

@interface KineticApplication : NSApplication
@end

@implementation KineticApplication

- (void)sendEvent:(NSEvent*)event {
    NSWindow* window = self.keyWindow ?: self.mainWindow;
    if (event.type == NSEventTypeKeyDown &&
        [window.firstResponder isKindOfClass:KineticToolPrompt.class]) {
        [super sendEvent:event];
        return;
    }
    if (kineticShortcutCommandForEvent(event) == KineticShortcutCommandCommandPalette) {
        [(id<KineticCommandHandler>)self.delegate showCommandPalette];
        return;
    }
    if (event.type == NSEventTypeKeyDown && !event.isARepeat &&
        [(id<KineticCommandHandler>)self.delegate executePluginShortcutForEvent:event]) {
        return;
    }
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
    case KineticShortcutCommandSearchWorkspace:
        [(id<KineticCommandHandler>)self.delegate focusWorkspaceSearch];
        return;
    case KineticShortcutCommandSearchFile:
        [(id<KineticCommandHandler>)self.delegate focusFileSearch];
        return;
    case KineticShortcutCommandSettings:
        [(id<KineticCommandHandler>)self.delegate showSettings];
        return;
    case KineticShortcutCommandCommandPalette:
        return;
    case KineticShortcutCommandPreviousTab:
        [(id<KineticCommandHandler>)self.delegate selectPreviousTab];
        return;
    case KineticShortcutCommandNextTab:
        [(id<KineticCommandHandler>)self.delegate selectNextTab];
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
    : NSObject <NSApplicationDelegate, KineticCommandHandler, KineticFileDialogDelegate,
                KineticPluginHostDelegate, KineticGitHubAccountDelegate,
                KineticEditorOverlayRenderer, KineticCommandPaletteDelegate,
                KineticCloneDialogDelegate>
@property(nonatomic, strong) NSWindow* window;
@property(nonatomic, strong) KineticWindowState* windowState;
@property(nonatomic, strong) NSView* content;
@property(nonatomic, strong) KineticHomeView* home;
@property(nonatomic, strong) KineticTrafficBar* trafficBar;
@property(nonatomic, strong) KineticEditorView* editor;
@property(nonatomic, strong) NSMutableArray<KineticEditorView*>* editors;
@property(nonatomic, strong) KineticFileDialog* fileDialog;
@property(nonatomic, strong) KineticCommandPalette* commandPalette;
@property(nonatomic, strong) KineticCloneDialog* cloneDialog;
@property(nonatomic) BOOL checkedCppTools;
@property(nonatomic, strong) KineticToolPrompt* toolPrompt;
@property(nonatomic, strong) NSTask* cloneTask;
@property(nonatomic, copy) NSString* pendingCloneUrl;
@property(nonatomic, strong) KineticPluginHost* pluginHost;
@property(nonatomic, copy) NSArray<NSDictionary<NSString*, id>*>* catalogPlugins;
@property(nonatomic, copy) NSString* pluginCatalogStatus;
@property(nonatomic) BOOL pluginManagerBusy;
@property(nonatomic, copy) NSString* appPackageStatus;
@property(nonatomic) BOOL appManagerBusy;
@property(nonatomic, strong) KineticGitHubAccount* githubAccount;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSNumber*>* pluginNumberOverrides;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSString*>* pluginStringOverrides;
@property(nonatomic, strong)
    NSMutableDictionary<NSString*, NSArray<NSDictionary<NSString*, id>*>*>* diagnosticsByPath;
@property(nonatomic, strong) NSURL* workspaceUrl;
@property(nonatomic, copy) NSDictionary* workspaceUiState;
@property(nonatomic, copy) NSDictionary* searchUiState;
@property(nonatomic) KineticActivitySection activitySection;
@property(nonatomic) NSUInteger untitledCounter;
@property(nonatomic) NSUInteger searchGeneration;
@end

@implementation KineticApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    (void)notification;

    self.editors = [NSMutableArray array];
    self.pluginNumberOverrides = [NSMutableDictionary dictionary];
    self.pluginStringOverrides = [NSMutableDictionary dictionary];
    self.diagnosticsByPath = [NSMutableDictionary dictionary];
    self.workspaceUiState = @{};
    self.searchUiState = @{};
    self.activitySection = KineticActivitySectionNone;
    self.catalogPlugins = @[];
    self.pluginCatalogStatus = @"Open Plugins to load the catalog.";
    self.appPackageStatus = @"Application updates are manual.";
    self.untitledCounter = 0;

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
    self.home.recentProjects = [self persistedRecentProjects];
    const CGFloat trafficBarHeight = [KineticTrafficBar preferredHeight];
    self.trafficBar = [[KineticTrafficBar alloc]
        initWithFrame:NSMakeRect(0.0, NSHeight(self.content.bounds) - trafficBarHeight,
                                 NSWidth(self.content.bounds), trafficBarHeight)];
    self.trafficBar.commandHandler = self;
    NSString* clientId = [NSBundle.mainBundle objectForInfoDictionaryKey:@"KineticGitHubClientId"];
    self.githubAccount = [[KineticGitHubAccount alloc] initWithClientId:clientId];
    self.githubAccount.delegate = self;
    self.trafficBar.githubAccount = self.githubAccount;
    [self.content addSubview:backdrop];
    [self.content addSubview:surface];
    [self.content addSubview:self.home];
    [self.content addSubview:self.trafficBar];
    self.window.contentView = self.content;
    self.windowState = [[KineticWindowState alloc] initWithWindow:self.window];
    if (![self.windowState restore]) {
        [self.window center];
    }
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self.githubAccount restoreSession];
}

- (void)githubAccountDidChange:(KineticGitHubAccount*)account {
    (void)account;
    [self.trafficBar accountDidChange];
}

- (NSArray<NSURL*>*)persistedRecentProjects {
    NSArray<NSString*>* paths =
        [NSUserDefaults.standardUserDefaults stringArrayForKey:@"kinetic.recentProjects"];
    NSMutableArray<NSURL*>* projects = [NSMutableArray array];
    for (NSString* path in paths ?: @[]) {
        BOOL directory = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory] &&
            directory) {
            [projects addObject:[NSURL fileURLWithPath:path isDirectory:YES]];
        }
    }
    return projects;
}

- (void)recordRecentProject:(NSURL*)projectUrl {
    NSMutableArray<NSString*>* paths = [NSMutableArray arrayWithObject:projectUrl.path];
    for (NSURL* existing in [self persistedRecentProjects]) {
        if (![existing.path isEqualToString:projectUrl.path]) {
            [paths addObject:existing.path];
        }
        if (paths.count >= 8) {
            break;
        }
    }
    [NSUserDefaults.standardUserDefaults setObject:paths forKey:@"kinetic.recentProjects"];
    self.home.recentProjects = [self persistedRecentProjects];
}

- (void)updateTabMetadata {
    NSMutableArray<NSString*>* titles = [NSMutableArray arrayWithCapacity:self.editors.count];
    NSMutableIndexSet* dirtyIndexes = [NSMutableIndexSet indexSet];
    for (NSUInteger index = 0; index < self.editors.count; ++index) {
        KineticEditorView* editor = self.editors[index];
        if (editor.workspacePlaceholder) {
            continue;
        }
        [titles addObject:editor.documentTitle];
        if (editor.dirty) {
            [dirtyIndexes addIndex:index];
        }
    }
    NSUInteger activeIndex =
        self.editor == nil ? NSNotFound : [self.editors indexOfObject:self.editor];
    for (KineticEditorView* editor in self.editors) {
        editor.tabTitles = titles;
        editor.dirtyTabIndexes = dirtyIndexes;
        editor.activeTabIndex = activeIndex == NSNotFound ? 0 : activeIndex;
    }
}

- (void)activateTabAtIndex:(NSUInteger)index {
    if (index >= self.editors.count) {
        return;
    }
    KineticEditorView* nextEditor = self.editors[index];
    KineticEditorView* previousEditor = self.editor;
    if (previousEditor != nil) {
        self.workspaceUiState = previousEditor.workspaceUiState;
        self.searchUiState = previousEditor.searchUiState;
        self.activitySection = previousEditor.activeActivitySection;
    }
    [nextEditor applyWorkspaceUiState:self.workspaceUiState];
    [nextEditor applySearchUiState:self.searchUiState];
    [nextEditor setActivitySection:self.activitySection animated:NO];
    [nextEditor setCatalogPlugins:self.catalogPlugins status:self.pluginCatalogStatus];
    [nextEditor setAppPackageStatus:self.appPackageStatus];
    if (self.activitySection == KineticActivitySectionPlugins && self.catalogPlugins.count == 0) {
        [self refreshPluginCatalog];
    }
    self.editor = nextEditor;
    nextEditor.diagnostics =
        nextEditor.fileUrl.path == nil
            ? @[]
            : (self.diagnosticsByPath[nextEditor.fileUrl.path.stringByResolvingSymlinksInPath]
                   ?: @[]);
    if (self.pluginHost == nil) {
        self.pluginHost = [[KineticPluginHost alloc] init];
        self.pluginHost.delegate = self;
        NSURL* pluginRootUrl = [KineticPluginHost userPluginRootUrl];
        NSURL* pluginsUrl = [pluginRootUrl URLByAppendingPathComponent:@"plugins" isDirectory:YES];
        NSURL* configurationUrl = [pluginRootUrl URLByAppendingPathComponent:@"config.toml"];
        NSURL* bundledPluginsUrl = [NSBundle.mainBundle.builtInPlugInsURL URLByStandardizingPath];
        [self.pluginHost loadPluginsAtUrl:bundledPluginsUrl configurationUrl:configurationUrl];
        [self.pluginHost loadPluginsAtUrl:pluginsUrl configurationUrl:configurationUrl];
        for (KineticEditorView* editor in self.editors) {
            [editor setPluginNames:self.pluginHost.loadedPluginNames
                          commands:self.pluginHost.commands
                configurationError:self.pluginHost.configurationError];
            [editor setPluginPanels:self.pluginHost.panels];
        }
    }
    [self.pluginHost emitEvent:@"document.activated"];
    [nextEditor setPluginPanels:self.pluginHost.panels];
    [self refreshPluginFileMenu];
    self.trafficBar.showsSearch = YES;
    self.trafficBar.searchActive = nextEditor.searchOpen;
    [self updateTabMetadata];
    if (previousEditor == nextEditor && nextEditor.superview != nil) {
        [self.window makeFirstResponder:nextEditor];
        [nextEditor focusSearchQuery];
        return;
    }

    NSRect finalFrame = self.content.bounds;
    nextEditor.frame = NSOffsetRect(finalFrame, 0.0, -5.0);
    nextEditor.alphaValue = 0.0;
    [self.content addSubview:nextEditor positioned:NSWindowBelow relativeTo:self.trafficBar];
    [KineticTween animateView:nextEditor
                      toFrame:finalFrame
                      toAlpha:1.0
                     duration:previousEditor == nil ? 0.18 : 0.11
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
    if (previousEditor != nil && previousEditor != nextEditor) {
        [KineticTween animateView:previousEditor
                          toFrame:NSOffsetRect(previousEditor.frame, 0.0, 5.0)
                          toAlpha:0.0
                         duration:0.12
                       completion:^{
                         [previousEditor removeFromSuperview];
                       }];
    }
    [self.window makeFirstResponder:nextEditor];
    [nextEditor focusSearchQuery];
}

- (void)selectPreviousTab {
    if (self.editors.count < 2 || self.editor == nil) {
        return;
    }
    NSUInteger index = [self.editors indexOfObject:self.editor];
    [self activateTabAtIndex:index == 0 ? self.editors.count - 1 : index - 1];
}

- (void)selectNextTab {
    if (self.editors.count < 2 || self.editor == nil) {
        return;
    }
    NSUInteger index = [self.editors indexOfObject:self.editor];
    [self activateTabAtIndex:(index + 1) % self.editors.count];
}

- (void)openEditorWithContents:(NSString*)contents fileUrl:(NSURL*)fileUrl {
    [self openEditorWithContents:contents fileUrl:fileUrl workspacePlaceholder:NO];
}

- (void)openWorkspacePlaceholder {
    [self openEditorWithContents:@"" fileUrl:nil workspacePlaceholder:YES];
}

- (void)openEditorWithContents:(NSString*)contents
                       fileUrl:(NSURL*)fileUrl
          workspacePlaceholder:(BOOL)workspacePlaceholder {
    if (!workspacePlaceholder && self.editor.workspacePlaceholder) {
        self.workspaceUiState = self.editor.workspaceUiState;
        self.searchUiState = self.editor.searchUiState;
        self.activitySection = self.editor.activeActivitySection;
        [self.editor removeFromSuperview];
        [self.editors removeObject:self.editor];
        self.editor = nil;
    }
    if (fileUrl != nil) {
        for (NSUInteger index = 0; index < self.editors.count; ++index) {
            if ([self.editors[index].fileUrl.path isEqualToString:fileUrl.path]) {
                [self activateTabAtIndex:index];
                return;
            }
        }
    }

    KineticEditorView* editor = [[KineticEditorView alloc] initWithFrame:self.content.bounds
                                                                contents:contents
                                                                 fileUrl:fileUrl];
    editor.workspacePlaceholder = workspacePlaceholder;
    editor.commandHandler = self;
    editor.overlayRenderer = self;
    [editor setPluginNames:self.pluginHost.loadedPluginNames
                  commands:self.pluginHost.commands
        configurationError:self.pluginHost.configurationError];
    [editor setPluginPanels:self.pluginHost.panels];
    [editor setCatalogPlugins:self.catalogPlugins status:self.pluginCatalogStatus];
    [editor setAppPackageStatus:self.appPackageStatus];
    for (NSString* property in self.pluginNumberOverrides) {
        [editor setPluginNumber:self.pluginNumberOverrides[property].doubleValue property:property];
    }
    for (NSString* property in self.pluginStringOverrides) {
        [editor setPluginString:self.pluginStringOverrides[property] property:property];
    }
    editor.workspaceUrl = self.workspaceUrl;
    [editor applyWorkspaceUiState:self.workspaceUiState];
    [editor applySearchUiState:self.searchUiState];
    [editor setActivitySection:self.activitySection animated:NO];
    if (workspacePlaceholder) {
        editor.documentTitle = @"";
    } else if (fileUrl == nil) {
        self.untitledCounter += 1;
        editor.documentTitle =
            [NSString stringWithFormat:@"Untitled-%lu", (unsigned long)self.untitledCounter];
    }
    [self.editors addObject:editor];
    [self activateTabAtIndex:self.editors.count - 1];
    [self checkToolsForFile:fileUrl];
}

- (void)installMissingTools:(NSArray<NSString*>*)names {
    if (names.count == 0) {
        [self.toolPrompt removeFromSuperview];
        self.toolPrompt = nil;
        [self.window makeFirstResponder:self.editor];
        [self.pluginHost emitEvent:@"document.activated"];
        return;
    }
    self.toolPrompt.busy = YES;
    self.toolPrompt.message = [NSString stringWithFormat:@"Installing %@…", names.firstObject];
    [self
        runPackageCommand:@[ @"tools", @"install", names.firstObject, @"--yes" ]
               completion:^(NSString* output, NSString* error) {
                 (void)output;
                 if (error != nil) {
                     self.toolPrompt.busy = NO;
                     self.toolPrompt.message = [NSString
                         stringWithFormat:@"Installation failed.\n%@\n\nTry again?", error];
                     return;
                 }
                 [self
                     installMissingTools:[names subarrayWithRange:NSMakeRange(1, names.count - 1)]];
               }];
}

- (void)checkToolsForFile:(NSURL*)url {
    if (self.checkedCppTools ||
        ![@[ @"c", @"h", @"cc", @"cpp", @"cxx", @"hpp", @"hh", @"hxx", @"m", @"mm" ]
            containsObject:url.pathExtension.lowercaseString])
        return;
    self.checkedCppTools = YES;
    [self runPackageCommand:@[ @"tools", @"status" ]
                 completion:^(NSString* output, NSString* error) {
                   if (error != nil) {
                       self.checkedCppTools = NO;
                       return;
                   }
                   NSDictionary* status = [NSJSONSerialization
                       JSONObjectWithData:[output dataUsingEncoding:NSUTF8StringEncoding]
                                  options:0
                                    error:nil];
                   if (![status isKindOfClass:NSDictionary.class]) {
                       self.checkedCppTools = NO;
                       return;
                   }
                   NSMutableArray* missing = [NSMutableArray array];
                   NSMutableArray* descriptions = [NSMutableArray array];
                   for (NSString* name in @[ @"clangd", @"clang-format" ]) {
                       if (![status[name] isKindOfClass:NSString.class]) {
                           [missing addObject:name];
                           [descriptions
                               addObject:[name isEqualToString:@"clangd"]
                                             ? @"clangd 23.1.0 — LLVM/clangd (Official), 100 MB"
                                             : @"clang-format 23.1.1 — PyPI clang-format "
                                               @"(Unofficial packaging), 1.6 MB"];
                       }
                   }
                   if (missing.count == 0)
                       return;
                   KineticToolPrompt* prompt =
                       [[KineticToolPrompt alloc] initWithFrame:self.content.bounds];
                   prompt.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
                   prompt.message = [NSString
                       stringWithFormat:@"Install missing tools?\n\n%@\n\nInstalled privately in "
                                        @"~/.kinetic/tools. No full LLVM toolchain.",
                                        [descriptions componentsJoinedByString:@"\n"]];
                   __weak __typeof__(self) weakSelf = self;
                   prompt.answer = ^(BOOL install) {
                     if (install)
                         [weakSelf installMissingTools:missing];
                     else {
                         [weakSelf.toolPrompt removeFromSuperview];
                         weakSelf.toolPrompt = nil;
                         [weakSelf.window makeFirstResponder:weakSelf.editor];
                     }
                   };
                   self.toolPrompt = prompt;
                   [self.content addSubview:prompt];
                   [self.window makeFirstResponder:prompt];
                 }];
}

- (void)newTextFile {
    [self openEditorWithContents:@"" fileUrl:nil];
}

- (void)editorDocumentDidChange {
    [self updateTabMetadata];
    [self.pluginHost emitEvent:@"document.changed"];
    [self.editor setPluginPanels:self.pluginHost.panels];
}

- (void)editorSettingDidChange:(NSString*)property value:(double)value {
    self.pluginNumberOverrides[property] = @(value);
    for (KineticEditorView* editor in self.editors) {
        [editor setPluginNumber:value property:property];
    }
}

- (void)executePluginCommand:(NSString*)commandId {
    if ([commandId isEqualToString:@"kinetic.formatDocument"]) {
        [self formatActiveDocument];
        return;
    }
    [self.pluginHost executeCommand:commandId];
}

- (void)showPluginCatalog:(NSArray<NSDictionary<NSString*, id>*>*)plugins status:(NSString*)status {
    NSMutableArray<NSDictionary<NSString*, id>*>* displayed = [NSMutableArray array];
    for (NSDictionary<NSString*, id>* plugin in plugins ?: @[]) {
        if ([plugin[@"id"] isEqualToString:@"kinetic.cpp-support"] &&
            self.pluginHost.loadedPluginVersions[@"kinetic.cpp-support"] != nil) {
            NSMutableDictionary<NSString*, id>* included = [plugin mutableCopy];
            included[@"state"] = @"included";
            included[@"version"] = self.pluginHost.loadedPluginVersions[@"kinetic.cpp-support"];
            [displayed addObject:included];
        } else {
            [displayed addObject:plugin];
        }
    }
    self.catalogPlugins = displayed;
    self.pluginCatalogStatus = status;
    for (KineticEditorView* editor in self.editors) {
        [editor setCatalogPlugins:self.catalogPlugins status:status];
    }
}

- (NSURL*)packageClientUrl {
    return [[NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"bin" isDirectory:YES]
        URLByAppendingPathComponent:@"kinetic"];
}

- (void)runPackageCommand:(NSArray<NSString*>*)arguments
               completion:(void (^)(NSString* output, NSString* errorMessage))completion {
    NSURL* executable = [self packageClientUrl];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSTask* task = [[NSTask alloc] init];
      task.executableURL = executable;
      task.arguments = arguments;
      NSPipe* outputPipe = [NSPipe pipe];
      task.standardOutput = outputPipe;
      task.standardError = outputPipe;
      NSError* launchError = nil;
      if (![task launchAndReturnError:&launchError]) {
          dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, launchError.localizedDescription ?: @"Could not start package client.");
          });
          return;
      }
      NSData* data = [outputPipe.fileHandleForReading readDataToEndOfFile];
      [task waitUntilExit];
      NSString* output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(task.terminationStatus == 0 ? output : nil,
                   task.terminationStatus == 0 ? nil : output);
      });
    });
}

- (void)refreshPluginCatalog {
    if (self.pluginManagerBusy) {
        return;
    }
    [self showPluginCatalog:self.catalogPlugins status:@"Checking the public catalog…"];
    [self runPackageCommand:@[ @"plugins", @"list", @"--json" ]
                 completion:^(NSString* output, NSString* errorMessage) {
                   if (errorMessage != nil) {
                       [self
                           showPluginCatalog:self.catalogPlugins
                                      status:[NSString stringWithFormat:@"Catalog unavailable: %@",
                                                                        errorMessage]];
                       return;
                   }
                   NSData* data = [output dataUsingEncoding:NSUTF8StringEncoding];
                   id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                   if (![parsed isKindOfClass:NSArray.class]) {
                       [self showPluginCatalog:self.catalogPlugins
                                        status:@"Catalog response was invalid."];
                       return;
                   }
                   [self showPluginCatalog:parsed
                                    status:[NSString
                                               stringWithFormat:@"%lu plugin%@ in catalog",
                                                                (unsigned long)[parsed count],
                                                                [parsed count] == 1 ? @"" : @"s"]];
                 }];
}

- (void)managePlugin:(NSDictionary<NSString*, id>*)plugin action:(NSString*)action {
    NSString* pluginId = plugin[@"id"];
    if (self.pluginManagerBusy || pluginId.length == 0 ||
        [plugin[@"state"] isEqualToString:@"included"] ||
        ![self.catalogPlugins containsObject:plugin] ||
        ![@[ @"install", @"update", @"uninstall" ] containsObject:action]) {
        return;
    }
    self.pluginManagerBusy = YES;
    [self showPluginCatalog:self.catalogPlugins
                     status:[NSString stringWithFormat:@"%@ %@…", action.capitalizedString,
                                                       plugin[@"name"] ?: pluginId]];
    [self runPackageCommand:@[ @"plugins", action, pluginId, @"--yes" ]
                 completion:^(NSString* output, NSString* errorMessage) {
                   self.pluginManagerBusy = NO;
                   if (errorMessage != nil) {
                       [self showPluginCatalog:self.catalogPlugins
                                        status:[NSString stringWithFormat:@"%@ failed: %@",
                                                                          action.capitalizedString,
                                                                          errorMessage]];
                       return;
                   }
                   [self
                       showPluginCatalog:self.catalogPlugins
                                  status:[output
                                             stringByTrimmingCharactersInSet:
                                                 NSCharacterSet.whitespaceAndNewlineCharacterSet]];
                   [self refreshPluginCatalog];
                 }];
}

- (void)showAppPackageStatus:(NSString*)status {
    self.appPackageStatus = status;
    for (KineticEditorView* editor in self.editors) {
        [editor setAppPackageStatus:status];
    }
}

- (void)manageApplication:(NSString*)action {
    if (self.appManagerBusy || ![@[ @"check", @"update", @"uninstall" ] containsObject:action]) {
        return;
    }
    if ([action isEqualToString:@"uninstall"]) {
        for (KineticEditorView* editor in self.editors) {
            if (editor.dirty) {
                [self showAppPackageStatus:@"Save or close unsaved tabs before uninstalling."];
                return;
            }
        }
    }
    NSString* command = action;
    if ([action isEqualToString:@"update"]) {
        NSString* target =
            [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/Kinetic.app"];
        if (![NSFileManager.defaultManager fileExistsAtPath:target]) {
            command = @"install";
        }
    }
    self.appManagerBusy = YES;
    [self showAppPackageStatus:[NSString
                                   stringWithFormat:@"%@ application…", action.capitalizedString]];
    [self
        runPackageCommand:@[ @"app", command, @"--yes" ]
               completion:^(NSString* output, NSString* errorMessage) {
                 self.appManagerBusy = NO;
                 NSString* message = errorMessage ?: output;
                 [self
                     showAppPackageStatus:[message
                                              stringByTrimmingCharactersInSet:
                                                  NSCharacterSet.whitespaceAndNewlineCharacterSet]];
               }];
}

- (void)refreshPluginFileMenu {
    NSMutableArray<NSDictionary<NSString*, NSString*>*>* items =
        [self.pluginHost.fileMenuItems mutableCopy] ?: [NSMutableArray array];
    NSString* fileName = self.editor.fileUrl.lastPathComponent ?: self.editor.documentTitle;
    if ([self.pluginHost hasFormatterForFileName:fileName]) {
        [items insertObject:@{@"id" : @"kinetic.formatDocument", @"title" : @"Format Document"}
                    atIndex:0];
    }
    self.trafficBar.fileMenuItems = items;
}

- (void)formatActiveDocument {
    if (self.editor == nil) {
        return;
    }
    NSString* fileName = self.editor.fileUrl.lastPathComponent ?: self.editor.documentTitle;
    NSString* original = self.editor.documentText;
    NSString* formatted = [self.pluginHost formatDocument:original fileName:fileName];
    if (formatted != nil && ![formatted isEqualToString:original]) {
        [self.editor replaceRangeFromPlugin:NSMakeRange(0, original.length) withString:formatted];
    }
}

- (void)drawPluginOverlaysInRect:(NSRect)rect {
    [self.pluginHost drawOverlaysInRect:rect];
}

- (NSArray<NSArray<NSDictionary<NSString*, id>*>*>*)pluginSyntaxTokensForLines:
                                                        (NSArray<NSString*>*)lines
                                                                      fileName:(NSString*)fileName {
    return [self.pluginHost syntaxTokensForLines:lines fileName:fileName];
}

- (NSArray<NSDictionary<NSString*, NSString*>*>*)pluginCompletionItemsForPrefix:(NSString*)prefix
                                                                       fileName:
                                                                           (NSString*)fileName {
    return [self.pluginHost completionItemsForPrefix:prefix fileName:fileName];
}

- (BOOL)hasPluginCompletionProviderForFileName:(NSString*)fileName {
    return [self.pluginHost hasCompletionProviderForFileName:fileName];
}

- (BOOL)applyPluginDiagnosticFixForPath:(NSString*)path
                                   line:(NSUInteger)line
                                 column:(NSUInteger)column
                                 length:(NSUInteger)length {
    return [self.pluginHost applyDiagnosticFixForPath:path line:line column:column length:length];
}

- (void)pluginHostContributionsDidChange:(KineticPluginHost*)host {
    [self refreshPluginFileMenu];
    for (KineticEditorView* editor in self.editors) {
        [editor setPluginNames:host.loadedPluginNames
                      commands:host.commands
            configurationError:host.configurationError];
        [editor setPluginPanels:host.panels];
        editor.needsDisplay = YES;
    }
}

- (BOOL)executePluginShortcutForEvent:(NSEvent*)event {
    NSEventModifierFlags flags = event.modifierFlags;
    uint32_t modifiers = 0;
    modifiers |= (flags & NSEventModifierFlagCommand) != 0 ? kineticPluginModifierCommand : 0;
    modifiers |= (flags & NSEventModifierFlagShift) != 0 ? kineticPluginModifierShift : 0;
    modifiers |= (flags & NSEventModifierFlagOption) != 0 ? kineticPluginModifierOption : 0;
    modifiers |= (flags & NSEventModifierFlagControl) != 0 ? kineticPluginModifierControl : 0;
    modifiers |= (flags & NSEventModifierFlagFunction) != 0 ? kineticPluginModifierFunction : 0;
    if (modifiers == 0) {
        return NO;
    }
    return [self.pluginHost executeShortcutKey:event.charactersIgnoringModifiers
                                     modifiers:modifiers];
}

- (BOOL)pluginHost:(KineticPluginHost*)host setNumber:(double)value property:(NSString*)property {
    (void)host;
    if (self.editor == nil || ![self.editor setPluginNumber:value property:property]) {
        return NO;
    }
    for (KineticEditorView* editor in self.editors) {
        if (editor != self.editor) {
            [editor setPluginNumber:value property:property];
        }
    }
    self.pluginNumberOverrides[property] = @(value);
    return YES;
}

- (BOOL)pluginHost:(KineticPluginHost*)host getNumber:(double*)value property:(NSString*)property {
    (void)host;
    return [self.editor getPluginNumber:value property:property];
}

- (BOOL)pluginHost:(KineticPluginHost*)host
         setString:(NSString*)value
          property:(NSString*)property {
    (void)host;
    if (self.editor == nil || ![self.editor setPluginString:value property:property]) {
        return NO;
    }
    for (KineticEditorView* editor in self.editors) {
        if (editor != self.editor) {
            [editor setPluginString:value property:property];
        }
    }
    self.pluginStringOverrides[property] = value;
    return YES;
}

- (NSString*)pluginHost:(KineticPluginHost*)host getString:(NSString*)property {
    (void)host;
    return [self.editor getPluginString:property];
}

- (NSString*)pluginHostActiveDocument:(KineticPluginHost*)host {
    (void)host;
    return self.editor.documentText;
}

- (NSString*)pluginHostActiveFilePath:(KineticPluginHost*)host {
    (void)host;
    return self.editor.fileUrl.path;
}

- (NSString*)pluginHostWorkspacePath:(KineticPluginHost*)host {
    (void)host;
    return self.workspaceUrl.path;
}

- (void)pluginHost:(KineticPluginHost*)host
    publishDiagnostics:(NSArray<NSDictionary<NSString*, id>*>*)diagnostics
               forPath:(NSString*)path {
    (void)host;
    NSString* resolvedPath = path.stringByResolvingSymlinksInPath;
    self.diagnosticsByPath[resolvedPath] = diagnostics;
    for (KineticEditorView* editor in self.editors) {
        if ([editor.fileUrl.path.stringByResolvingSymlinksInPath isEqualToString:resolvedPath]) {
            editor.diagnostics = diagnostics;
        }
    }
    [self.editor setPluginPanels:self.pluginHost.panels];
}

- (void)pluginHost:(KineticPluginHost*)host
    openLocationAtPath:(NSString*)path
                  line:(NSUInteger)line
                column:(NSUInteger)column {
    (void)host;
    NSURL* url = [NSURL fileURLWithPath:path];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        return;
    }
    [self openFileAtUrl:url];
    [self.editor revealLine:line column:column + 1 length:0];
}

- (BOOL)pluginHost:(KineticPluginHost*)host replaceSelection:(NSString*)text {
    (void)host;
    if (self.editor == nil) {
        return NO;
    }
    [self.editor replaceSelectionFromPlugin:text];
    return YES;
}

- (BOOL)pluginHost:(KineticPluginHost*)host getSelection:(NSRange*)selection {
    (void)host;
    if (self.editor == nil || selection == nullptr) {
        return NO;
    }
    *selection = self.editor.pluginSelection;
    return YES;
}

- (BOOL)pluginHost:(KineticPluginHost*)host setSelection:(NSRange)selection {
    (void)host;
    return [self.editor setPluginSelection:selection];
}

- (BOOL)pluginHost:(KineticPluginHost*)host replaceRange:(NSRange)range withString:(NSString*)text {
    (void)host;
    return [self.editor replaceRangeFromPlugin:range withString:text];
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

- (void)searchWorkspaceForQuery:(NSString*)query matchCase:(BOOL)matchCase {
    NSUInteger generation = ++self.searchGeneration;
    NSURL* workspaceUrl = self.workspaceUrl;
    if (self.editor == nil || workspaceUrl == nil || query.length == 0) {
        [self.editor applySearchResults:@[] loading:NO truncated:NO];
        self.searchUiState = self.editor.searchUiState ?: @{};
        return;
    }

    [self.editor applySearchResults:@[] loading:YES truncated:NO];
    self.searchUiState = self.editor.searchUiState;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     if (generation != self.searchGeneration ||
                         ![workspaceUrl.path isEqualToString:self.workspaceUrl.path]) {
                         return;
                     }
                     NSMutableDictionary<NSString*, NSString*>* openDocuments =
                         [NSMutableDictionary dictionary];
                     for (KineticEditorView* editor in self.editors) {
                         if (editor.fileUrl != nil) {
                             openDocuments[editor.fileUrl.path] = editor.documentText;
                         }
                     }
                     dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                       BOOL truncated = NO;
                       NSArray<NSDictionary*>* results = kineticSearchWorkspace(
                           workspaceUrl, query, matchCase, openDocuments, 300, &truncated);
                       dispatch_async(dispatch_get_main_queue(), ^{
                         if (generation != self.searchGeneration || self.editor == nil ||
                             self.editor.searchScope != KineticSearchScopeProject ||
                             ![workspaceUrl.path isEqualToString:self.workspaceUrl.path]) {
                             return;
                         }
                         [self.editor applySearchResults:results loading:NO truncated:truncated];
                         self.searchUiState = self.editor.searchUiState;
                       });
                     });
                   });
}

- (void)focusWorkspaceSearch {
    if (self.editor == nil) {
        return;
    }
    [self.editor focusWorkspaceSearch];
    self.searchUiState = self.editor.searchUiState;
}

- (void)focusFileSearch {
    if (self.editor == nil) {
        return;
    }
    [self.editor focusFileSearch];
    self.searchUiState = self.editor.searchUiState;
}

- (void)showSettings {
    if (self.editor == nil) {
        return;
    }
    self.activitySection = KineticActivitySectionSettings;
    [self.editor setActivitySection:KineticActivitySectionSettings animated:YES];
}

- (void)showCommandPalette {
    if (self.commandPalette != nil) {
        [self commandPaletteDidClose:self.commandPalette];
        return;
    }
    NSMutableArray<NSDictionary<NSString*, NSString*>*>* commands =
        [NSMutableArray arrayWithArray:@[
            @{
                @"id" : @"newFile",
                @"title" : @"New Text File",
                @"shortcut" : @"⌘N",
                @"category" : @"File"
            },
            @{
                @"id" : @"openFile",
                @"title" : @"Open File…",
                @"shortcut" : @"⌘O",
                @"category" : @"File"
            },
            @{
                @"id" : @"openFolder",
                @"title" : @"Open Folder…",
                @"shortcut" : @"",
                @"category" : @"File"
            },
            @{
                @"id" : @"clone",
                @"title" : @"Clone Repository…",
                @"shortcut" : @"",
                @"category" : @"Git"
            },
            @{@"id" : @"themeDark", @"title" : @"Theme: Kinetic Dark", @"category" : @"Appearance"},
            @{@"id" : @"themeMidnight", @"title" : @"Theme: Midnight", @"category" : @"Appearance"},
            @{@"id" : @"themeGraphite", @"title" : @"Theme: Graphite", @"category" : @"Appearance"},
        ]];
    if (self.editor != nil) {
        [commands addObjectsFromArray:@[
            @{@"id" : @"save", @"title" : @"Save File", @"shortcut" : @"⌘S", @"category" : @"File"},
            @{
                @"id" : @"closeTab",
                @"title" : @"Close Tab",
                @"shortcut" : @"⌘W",
                @"category" : @"File"
            },
            @{
                @"id" : @"findFile",
                @"title" : @"Find in File",
                @"shortcut" : @"⌘F",
                @"category" : @"Search"
            },
            @{
                @"id" : @"findProject",
                @"title" : @"Find in Project",
                @"shortcut" : @"⇧⌘F",
                @"category" : @"Search"
            },
            @{
                @"id" : @"plugins",
                @"title" : @"Show Plugins",
                @"shortcut" : @"",
                @"category" : @"View"
            },
            @{
                @"id" : @"settings",
                @"title" : @"Show Settings",
                @"shortcut" : @"⌘,",
                @"category" : @"View"
            },
        ]];
        for (NSDictionary<NSString*, NSString*>* pluginCommand in self.pluginHost.commands) {
            NSString* identifier = pluginCommand[@"id"];
            NSString* title = pluginCommand[@"title"];
            if (identifier.length > 0 && title.length > 0) {
                [commands addObject:@{
                    @"id" : [@"plugin:" stringByAppendingString:identifier],
                    @"title" : title,
                    @"shortcut" : @"",
                    @"category" : @"Extension"
                }];
            }
        }
    }
    KineticCommandPalette* palette =
        [[KineticCommandPalette alloc] initWithFrame:self.content.bounds];
    palette.delegate = self;
    palette.commands = commands;
    palette.alphaValue = 0.0;
    self.commandPalette = palette;
    [self.content addSubview:palette positioned:NSWindowAbove relativeTo:nil];
    [KineticTween animateView:palette
                      toFrame:palette.frame
                      toAlpha:1.0
                     duration:0.12
                   completion:nil];
    [palette focusQuery];
}

- (void)commandPaletteDidClose:(KineticCommandPalette*)palette {
    if (palette != self.commandPalette) {
        return;
    }
    self.commandPalette = nil;
    [KineticTween animateView:palette
                      toFrame:palette.frame
                      toAlpha:0.0
                     duration:0.1
                   completion:^{
                     [palette removeFromSuperview];
                   }];
    [self.window makeFirstResponder:self.editor ?: self.home];
}

- (void)commandPalette:(KineticCommandPalette*)palette didChooseCommand:(NSString*)commandId {
    [self commandPaletteDidClose:palette];
    if ([commandId isEqualToString:@"newFile"]) {
        [self newTextFile];
    } else if ([commandId isEqualToString:@"openFile"]) {
        [self openFile];
    } else if ([commandId isEqualToString:@"openFolder"]) {
        [self openFolder];
    } else if ([commandId isEqualToString:@"clone"]) {
        [self cloneRepository];
    } else if ([commandId hasPrefix:@"theme"]) {
        NSString* name = [commandId isEqualToString:@"themeMidnight"]   ? @"midnight"
                         : [commandId isEqualToString:@"themeGraphite"] ? @"graphite"
                                                                        : @"kinetic-dark";
        kineticSetThemeName(name);
        self.pluginNumberOverrides[@"interface.theme"] =
            @([name isEqualToString:@"midnight"]   ? 1
              : [name isEqualToString:@"graphite"] ? 2
                                                   : 0);
        kineticRefreshThemeInView(self.content);
        for (KineticEditorView* editor in self.editors) {
            kineticRefreshThemeInView(editor);
        }
    } else if ([commandId isEqualToString:@"save"]) {
        [self saveFile];
    } else if ([commandId isEqualToString:@"closeTab"]) {
        [self closeActiveTab];
    } else if ([commandId isEqualToString:@"findFile"]) {
        [self focusFileSearch];
    } else if ([commandId isEqualToString:@"findProject"]) {
        [self focusWorkspaceSearch];
    } else if ([commandId isEqualToString:@"plugins"]) {
        self.activitySection = KineticActivitySectionPlugins;
        [self.editor setActivitySection:KineticActivitySectionPlugins animated:YES];
        [self refreshPluginCatalog];
    } else if ([commandId isEqualToString:@"settings"]) {
        [self showSettings];
    } else if ([commandId hasPrefix:@"plugin:"]) {
        [self executePluginCommand:[commandId substringFromIndex:7]];
    }
}

- (void)toggleFileSearch {
    if (self.editor == nil) {
        return;
    }
    [self.editor toggleFileSearch];
    self.searchUiState = self.editor.searchUiState;
}

- (void)searchVisibilityDidChange:(BOOL)visible {
    self.trafficBar.searchActive = visible;
}

- (void)openSearchResult:(NSDictionary*)result {
    NSURL* fileUrl = result[@"url"];
    if (![fileUrl isKindOfClass:NSURL.class]) {
        return;
    }
    [self openFileAtUrl:fileUrl];
    [self.editor revealLine:[result[@"line"] unsignedIntegerValue]
                     column:[result[@"column"] unsignedIntegerValue]
                     length:[result[@"length"] unsignedIntegerValue]];
}

- (void)openFolder {
    [self presentFileDialogWithMode:KineticFileDialogModeOpenFolder initialPath:@"~/"];
}

- (void)cloneRepository {
    if (self.cloneDialog != nil) {
        [self.cloneDialog focusUrl];
        return;
    }
    KineticCloneDialog* dialog = [[KineticCloneDialog alloc] initWithFrame:self.content.bounds];
    dialog.delegate = self;
    dialog.alphaValue = 0.0;
    self.cloneDialog = dialog;
    [self.content addSubview:dialog positioned:NSWindowAbove relativeTo:nil];
    [KineticTween animateView:dialog toFrame:dialog.frame toAlpha:1.0 duration:0.14 completion:nil];
    [dialog focusUrl];
}

- (void)cloneDialogDidCancel:(KineticCloneDialog*)dialog {
    if (dialog != self.cloneDialog) {
        return;
    }
    if (self.cloneTask.isRunning) {
        [self.cloneTask terminate];
    }
    self.pendingCloneUrl = nil;
    self.cloneDialog = nil;
    [KineticTween animateView:dialog
                      toFrame:dialog.frame
                      toAlpha:0.0
                     duration:0.1
                   completion:^{
                     [dialog removeFromSuperview];
                   }];
    [self.window makeFirstResponder:self.editor ?: self.home];
}

- (void)cloneDialog:(KineticCloneDialog*)dialog didRequestDestinationForUrl:(NSString*)url {
    NSString* trimmed =
        [url stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURLComponents* components = [NSURLComponents componentsWithString:trimmed];
    NSString* repositoryName = components.path.lastPathComponent;
    if ([repositoryName hasSuffix:@".git"]) {
        repositoryName = [repositoryName substringToIndex:repositoryName.length - 4];
    }
    NSCharacterSet* invalidName = [[NSCharacterSet
        characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"] invertedSet];
    if (![components.scheme.lowercaseString isEqualToString:@"https"] ||
        components.host.length == 0 || components.user != nil || components.password != nil ||
        components.query != nil || components.fragment != nil ||
        [trimmed rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                .location != NSNotFound ||
        repositoryName.length == 0 || [repositoryName isEqualToString:@"."] ||
        [repositoryName isEqualToString:@".."] ||
        [repositoryName rangeOfCharacterFromSet:invalidName].location != NSNotFound) {
        dialog.status = @"Enter an HTTPS repository URL without credentials or query text.";
        return;
    }
    self.pendingCloneUrl = trimmed;
    dialog.status = @"Choose the parent folder for the new repository.";
    [self presentFileDialogWithMode:KineticFileDialogModeOpenFolder initialPath:@"~/"];
}

- (void)startCloneIntoDirectory:(NSURL*)parentUrl {
    NSString* repositoryUrl = self.pendingCloneUrl;
    self.pendingCloneUrl = nil;
    NSString* repositoryName =
        [NSURLComponents componentsWithString:repositoryUrl].path.lastPathComponent;
    if ([repositoryName hasSuffix:@".git"]) {
        repositoryName = [repositoryName substringToIndex:repositoryName.length - 4];
    }
    NSURL* targetUrl = [parentUrl URLByAppendingPathComponent:repositoryName isDirectory:YES];
    if ([NSFileManager.defaultManager fileExistsAtPath:targetUrl.path]) {
        self.cloneDialog.status =
            @"A file or folder with that repository name already exists here.";
        [self.cloneDialog focusUrl];
        return;
    }
    KineticCloneDialog* dialog = self.cloneDialog;
    dialog.busy = YES;
    dialog.status = [NSString stringWithFormat:@"Cloning %@…", repositoryName];
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/git"];
    task.arguments = @[ @"clone", @"--", repositoryUrl, targetUrl.path ];
    NSMutableDictionary<NSString*, NSString*>* environment =
        [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"GIT_TERMINAL_PROMPT"] = @"0";
    environment[@"GIT_ASKPASS"] = @"/usr/bin/false";
    task.environment = environment;
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    NSPipe* output = [NSPipe pipe];
    task.standardError = output;
    task.standardOutput = output;
    self.cloneTask = task;
    NSError* launchError = nil;
    BOOL launched = [task launchAndReturnError:&launchError];
    if (!launched) {
        self.cloneTask = nil;
        dialog.busy = NO;
        dialog.status =
            [NSString stringWithFormat:@"Clone could not start: %@",
                                       launchError.localizedDescription ?: @"Git is unavailable."];
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSData* data = [output.fileHandleForReading readDataToEndOfFile];
      [task waitUntilExit];
      NSString* message = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
      dispatch_async(dispatch_get_main_queue(), ^{
        if (self.cloneTask == task) {
            self.cloneTask = nil;
        }
        if (self.cloneDialog != dialog) {
            return;
        }
        dialog.busy = NO;
        if (task.terminationStatus == 0) {
            [self cloneDialogDidCancel:dialog];
            [self openRecentProjectAtUrl:targetUrl];
        } else {
            NSString* detail = message;
            detail = [detail
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            dialog.status =
                detail.length > 0
                    ? [NSString
                          stringWithFormat:@"Clone failed: %@",
                                           [detail substringFromIndex:detail.length > 180
                                                                          ? detail.length - 180
                                                                          : 0]]
                    : @"Clone failed. Check the URL, connection, and Git credentials.";
        }
      });
    });
}

- (void)createFolder {
    if (self.workspaceUrl == nil) {
        return;
    }
    [self presentFileDialogWithMode:KineticFileDialogModeCreateFolder
                        initialPath:self.workspaceUrl.path];
}

- (void)createFileInDirectory:(NSURL*)directoryUrl {
    if (self.workspaceUrl == nil || directoryUrl == nil) {
        return;
    }
    [self presentFileDialogWithMode:KineticFileDialogModeCreateFile initialPath:directoryUrl.path];
}

- (void)createFolderInDirectory:(NSURL*)directoryUrl {
    if (self.workspaceUrl == nil || directoryUrl == nil) {
        return;
    }
    [self presentFileDialogWithMode:KineticFileDialogModeCreateFolder
                        initialPath:directoryUrl.path];
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
    [self updateTabMetadata];
    [self checkToolsForFile:fileUrl];
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
    if (self.cloneDialog != nil) {
        [self.cloneDialog focusUrl];
    } else {
        [self.window makeFirstResponder:self.editor ?: self.home];
    }
}

- (void)fileDialog:(KineticFileDialog*)dialog
     didChoosePath:(NSString*)path
              mode:(KineticFileDialogMode)mode {
    NSURL* fileUrl = [NSURL fileURLWithPath:path];
    if (mode == KineticFileDialogModeCreateFolder || mode == KineticFileDialogModeCreateFile) {
        NSURL* parentUrl = [fileUrl URLByDeletingLastPathComponent];
        NSString* workspacePath =
            [[[self.workspaceUrl URLByResolvingSymlinksInPath] path] stringByStandardizingPath];
        NSString* parentPath =
            [[[parentUrl URLByResolvingSymlinksInPath] path] stringByStandardizingPath];
        if (workspacePath == nil ||
            !([parentPath isEqualToString:workspacePath] ||
              [parentPath hasPrefix:[workspacePath stringByAppendingString:@"/"]])) {
            [dialog showError:@"Choose a folder inside this project."];
            return;
        }
        if ([NSFileManager.defaultManager fileExistsAtPath:fileUrl.path]) {
            [dialog showError:@"A file or folder with that name already exists."];
            return;
        }
        NSError* error = nil;
        if (mode == KineticFileDialogModeCreateFolder) {
            if (![NSFileManager.defaultManager createDirectoryAtURL:fileUrl
                                        withIntermediateDirectories:NO
                                                         attributes:nil
                                                              error:&error]) {
                [dialog showError:@"Kinetic could not create this folder."];
                return;
            }
            [self.editor revealCreatedFolderAtUrl:fileUrl];
        } else {
            int descriptor =
                open(fileUrl.fileSystemRepresentation, O_CREAT | O_EXCL | O_WRONLY, 0666);
            if (descriptor < 0) {
                [dialog showError:@"Kinetic could not create this file."];
                return;
            }
            close(descriptor);
            [self.editor revealCreatedFileAtUrl:fileUrl];
        }
        self.workspaceUiState = self.editor.workspaceUiState;
        [self dismissFileDialog];
        if (mode == KineticFileDialogModeCreateFile) {
            [self openFileAtUrl:fileUrl];
        }
        return;
    }
    if (mode == KineticFileDialogModeOpenFolder) {
        BOOL isDirectory = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] ||
            !isDirectory) {
            [dialog showError:@"That folder does not exist."];
            return;
        }
        if (self.pendingCloneUrl != nil) {
            [self dismissFileDialog];
            [self startCloneIntoDirectory:fileUrl];
            return;
        }
        ++self.searchGeneration;
        self.workspaceUrl = fileUrl;
        self.searchUiState = @{};
        self.activitySection = KineticActivitySectionExplorer;
        [self recordRecentProject:fileUrl];
        [self dismissFileDialog];
        if (self.editor == nil) {
            self.workspaceUiState = @{};
            [self openWorkspacePlaceholder];
        } else {
            for (KineticEditorView* editor in self.editors) {
                editor.workspaceUrl = fileUrl;
                [editor applySearchUiState:@{}];
                [editor setActivitySection:self.activitySection animated:YES];
            }
            self.workspaceUiState = self.editor.workspaceUiState;
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
        self.pendingCloneUrl = nil;
        [self dismissFileDialog];
    }
}

- (BOOL)closeActiveTab {
    if ([self.editor closeUtilityPanelIfOpen])
        return YES;
    if (self.editor == nil) {
        return NO;
    }
    NSUInteger activeIndex = [self.editors indexOfObject:self.editor];
    return [self closeTabAtIndex:activeIndex];
}

- (BOOL)closeTabAtIndex:(NSUInteger)index {
    if (index >= self.editors.count) {
        return NO;
    }

    KineticEditorView* closingEditor = self.editors[index];
    if (closingEditor.workspacePlaceholder) {
        return NO;
    }
    KineticEditorView* stateOwner = self.editor ?: closingEditor;
    self.workspaceUiState = stateOwner.workspaceUiState;
    self.searchUiState = stateOwner.searchUiState;
    self.activitySection = stateOwner.activeActivitySection;
    BOOL closesActiveEditor = closingEditor == self.editor;
    [self.editors removeObjectAtIndex:index];
    if (!closesActiveEditor) {
        [self updateTabMetadata];
        return YES;
    }

    self.editor = nil;
    if (self.editors.count > 0) {
        NSUInteger nextIndex = MIN(index, self.editors.count - 1);
        [closingEditor removeFromSuperview];
        [self activateTabAtIndex:nextIndex];
        return YES;
    }

    if (self.workspaceUrl != nil) {
        [closingEditor removeFromSuperview];
        [self openWorkspacePlaceholder];
        return YES;
    }

    self.home.hidden = NO;
    [self refreshPluginFileMenu];
    self.trafficBar.showsSearch = NO;
    self.trafficBar.searchActive = NO;
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

- (void)openRecentProjectAtUrl:(NSURL*)projectUrl {
    BOOL directory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:projectUrl.path isDirectory:&directory] ||
        !directory) {
        self.home.recentProjects = [self persistedRecentProjects];
        return;
    }
    ++self.searchGeneration;
    self.workspaceUrl = projectUrl;
    self.searchUiState = @{};
    self.activitySection = KineticActivitySectionExplorer;
    [self recordRecentProject:projectUrl];
    for (KineticEditorView* editor in self.editors) {
        editor.workspaceUrl = projectUrl;
        [editor applySearchUiState:@{}];
        [editor setActivitySection:self.activitySection animated:YES];
    }
    if (self.editor != nil) {
        self.workspaceUiState = self.editor.workspaceUiState;
    } else {
        self.workspaceUiState = @{};
    }
    if (self.editor == nil) {
        [self openWorkspacePlaceholder];
    }
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
