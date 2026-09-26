#pragma once

#import <Foundation/Foundation.h>

@protocol KineticCommandHandler <NSObject>
- (void)newTextFile;
- (void)openFile;
- (void)openFileAtUrl:(NSURL*)fileUrl;
- (void)openFolder;
- (void)saveFile;
- (BOOL)closeActiveTab;
@end
