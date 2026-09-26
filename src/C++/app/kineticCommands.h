#pragma once

#import <Foundation/Foundation.h>

@protocol KineticCommandHandler <NSObject>
- (void)newTextFile;
- (void)openFile;
- (void)openFileAtUrl:(NSURL*)fileUrl;
- (void)openFolder;
- (void)createFolder;
- (void)searchWorkspaceForQuery:(NSString*)query matchCase:(BOOL)matchCase;
- (void)focusWorkspaceSearch;
- (void)focusFileSearch;
- (void)toggleFileSearch;
- (void)searchVisibilityDidChange:(BOOL)visible;
- (void)openSearchResult:(NSDictionary*)result;
- (void)openRecentProjectAtUrl:(NSURL*)projectUrl;
- (void)saveFile;
- (BOOL)closeActiveTab;
- (void)activateTabAtIndex:(NSUInteger)index;
- (BOOL)closeTabAtIndex:(NSUInteger)index;
- (void)selectPreviousTab;
- (void)selectNextTab;
@end
