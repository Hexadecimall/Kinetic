#pragma once

#import <Foundation/Foundation.h>

@protocol KineticCommandHandler <NSObject>
- (void)newTextFile;
- (void)openFile;
- (void)openFileAtUrl:(NSURL*)fileUrl;
- (void)openFolder;
- (void)openRecentProjectAtUrl:(NSURL*)projectUrl;
- (void)saveFile;
- (BOOL)closeActiveTab;
- (void)activateTabAtIndex:(NSUInteger)index;
- (BOOL)closeTabAtIndex:(NSUInteger)index;
- (void)selectPreviousTab;
- (void)selectNextTab;
@end
