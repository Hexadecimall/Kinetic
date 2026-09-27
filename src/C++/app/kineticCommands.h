#pragma once

#import <AppKit/AppKit.h>

@protocol KineticCommandHandler <NSObject>
- (void)newTextFile;
- (void)openFile;
- (void)openFileAtUrl:(NSURL*)fileUrl;
- (void)openFolder;
- (void)createFolder;
- (void)createFileInDirectory:(NSURL*)directoryUrl;
- (void)createFolderInDirectory:(NSURL*)directoryUrl;
- (void)searchWorkspaceForQuery:(NSString*)query matchCase:(BOOL)matchCase;
- (void)focusWorkspaceSearch;
- (void)focusFileSearch;
- (void)toggleFileSearch;
- (void)searchVisibilityDidChange:(BOOL)visible;
- (void)editorDocumentDidChange;
- (void)executePluginCommand:(NSString*)commandId;
- (BOOL)executePluginShortcutForEvent:(NSEvent*)event;
- (void)openSearchResult:(NSDictionary*)result;
- (void)openRecentProjectAtUrl:(NSURL*)projectUrl;
- (void)saveFile;
- (BOOL)closeActiveTab;
- (void)activateTabAtIndex:(NSUInteger)index;
- (BOOL)closeTabAtIndex:(NSUInteger)index;
- (void)selectPreviousTab;
- (void)selectNextTab;
@end
