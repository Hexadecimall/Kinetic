#import "editorStructure.h"
#import "fileDialog.h"

#import <AppKit/AppKit.h>

@interface KineticFileDialog (SearchTest)
- (void)controlTextDidChange:(NSNotification*)notification;
@end

static BOOL check(BOOL condition, NSString* message) {
    if (!condition) {
        NSLog(@"%@", message);
    }
    return condition;
}

int main() {
    @autoreleasepool {
        NSFileManager* manager = NSFileManager.defaultManager;
        NSURL* root =
            [NSURL fileURLWithPath:[NSTemporaryDirectory()
                                       stringByAppendingPathComponent:
                                           [NSString stringWithFormat:@"kinetic-dialog-%@",
                                                                      NSUUID.UUID.UUIDString]]
                       isDirectory:YES];
        NSError* error = nil;
        if (![manager createDirectoryAtURL:root
                withIntermediateDirectories:NO
                                 attributes:nil
                                      error:&error]) {
            NSLog(@"Could not create dialog test fixture: %@", error);
            return 1;
        }
        NSURL* hiddenFolder = [root URLByAppendingPathComponent:@".hiddenFolder" isDirectory:YES];
        NSURL* hiddenFile = [root URLByAppendingPathComponent:@".hiddenFile"];
        NSURL* linkedFolder = [root URLByAppendingPathComponent:@"linkedFolder" isDirectory:YES];
        BOOL setup = [manager createDirectoryAtURL:hiddenFolder
                         withIntermediateDirectories:NO
                                          attributes:nil
                                               error:&error] &&
                     [@"" writeToURL:hiddenFile
                          atomically:YES
                            encoding:NSUTF8StringEncoding
                               error:&error] &&
                     [manager createSymbolicLinkAtURL:linkedFolder
                                   withDestinationURL:hiddenFolder
                                                error:&error];
        BOOL passed = setup;
        passed &=
            check(NSEqualRanges(kineticDeleteToLineStartRange(@"one\ntwo", 6), NSMakeRange(4, 2)),
                  @"Command-Delete stops at the current line start");
        passed &= check(NSEqualRanges(kineticDeleteToLineStartRange(@"", 0), NSMakeRange(0, 0)),
                        @"Empty line deletion is safe");
        for (NSNumber* mode in @[
                 @(KineticFileDialogModeSave), @(KineticFileDialogModeCreateFile),
                 @(KineticFileDialogModeCreateFolder)
             ]) {
            KineticFileDialog* nameDialog =
                [[KineticFileDialog alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)
                                                    mode:(KineticFileDialogMode)mode.integerValue
                                             initialPath:root.path
                                                delegate:nil];
            NSMutableString* name = [nameDialog valueForKey:@"fileName"];
            [name setString:@"example.cpp"];
            NSEvent* deleteKey = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                                  location:NSZeroPoint
                                             modifierFlags:NSEventModifierFlagCommand
                                                 timestamp:0
                                              windowNumber:0
                                                   context:nil
                                                characters:@"\177"
                               charactersIgnoringModifiers:@"\177"
                                                 isARepeat:NO
                                                   keyCode:51];
            [nameDialog keyDown:deleteKey];
            passed &= check(name.length == 0, @"Command-Delete clears the name field");
            [nameDialog keyDown:deleteKey];
            passed &= check(name.length == 0, @"Command-Delete on an empty name is safe");
            [name setString:@"file😀"];
            NSEvent* backspace = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                                  location:NSZeroPoint
                                             modifierFlags:0
                                                 timestamp:0
                                              windowNumber:0
                                                   context:nil
                                                characters:@"\177"
                               charactersIgnoringModifiers:@"\177"
                                                 isARepeat:NO
                                                   keyCode:51];
            [nameDialog keyDown:backspace];
            passed &= check([name isEqualToString:@"file"], @"Backspace removes one grapheme");
        }
        if (setup) {
            KineticFileDialog* dialog =
                [[KineticFileDialog alloc] initWithFrame:NSMakeRect(0.0, 0.0, 800.0, 600.0)
                                                    mode:KineticFileDialogModeOpenFolder
                                             initialPath:root.path
                                                delegate:nil];
            NSArray* entries = [dialog valueForKey:@"_entries"];
            NSMutableDictionary<NSString*, NSNumber*>* directories =
                [NSMutableDictionary dictionary];
            for (id entry in entries) {
                directories[[entry valueForKey:@"name"]] = [entry valueForKey:@"directory"];
            }
            passed = passed &&
                     check([directories[@".hiddenFolder"] boolValue],
                           @"Hidden folder missing from Open Folder") &&
                     check(directories[@".hiddenFile"] != nil &&
                               ![directories[@".hiddenFile"] boolValue],
                           @"Hidden file missing from Open Folder") &&
                     check([directories[@"linkedFolder"] boolValue],
                           @"Directory symlink did not behave as a folder");
            NSTextField* search = [dialog valueForKey:@"_searchField"];
            search.stringValue = @"hidden";
            [dialog controlTextDidChange:[NSNotification
                                             notificationWithName:NSControlTextDidChangeNotification
                                                           object:search]];
            NSArray* filtered = [dialog valueForKey:@"_entries"];
            passed =
                check(filtered.count == 2, @"File picker search did not filter entries") && passed;
        } else {
            NSLog(@"Could not populate dialog test fixture: %@", error);
        }
        [manager removeItemAtURL:root error:nil];
        return passed ? 0 : 1;
    }
}
