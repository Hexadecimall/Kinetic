#import "editorView.h"

#import <AppKit/AppKit.h>

@interface KineticEditorView (HistoryTest)
- (void)undoEdit;
- (void)redoEdit;
@end

static BOOL check(BOOL condition, NSString* message) {
    if (!condition) {
        NSLog(@"Editor backend integration failed: %@", message);
    }
    return condition;
}

int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        KineticEditorView* editor =
            [[KineticEditorView alloc] initWithFrame:NSMakeRect(0, 0, 1180, 760)
                                            contents:@"initial"
                                             fileUrl:nil];
        BOOL passed =
            check([editor.documentText isEqualToString:@"initial"], @"initial text") &&
            check(!editor.dirty, @"initial save state") &&
            check([editor setPluginString:@"#203040" property:@"editor.canvas.background"],
                  @"canvas property") &&
            check([[editor getPluginString:@"editor.canvas.background"] isEqualToString:@"#203040"],
                  @"canvas property readback") &&
            check(![editor setPluginString:@"blue" property:@"editor.canvas.background"],
                  @"invalid canvas color") &&
            check([editor replaceRangeFromPlugin:NSMakeRange(0, 7) withString:@"hello"],
                  @"range edit") &&
            check([editor.documentText isEqualToString:@"hello"], @"edited text") &&
            check(editor.dirty, @"dirty after edit") &&
            check(NSEqualRanges(editor.pluginSelection, NSMakeRange(5, 0)), @"caret after edit");
        [editor undoEdit];
        passed = check([editor.documentText isEqualToString:@"initial"], @"undo text") &&
                 check(!editor.dirty, @"undo save state") && passed;
        [editor redoEdit];
        passed = check([editor.documentText isEqualToString:@"hello"], @"redo text") &&
                 check(editor.dirty, @"redo dirty state") && passed;
        [editor markSaved];
        passed = check(!editor.dirty, @"mark saved") && passed;
        NSEvent* key = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                        location:NSZeroPoint
                                   modifierFlags:0
                                       timestamp:0
                                    windowNumber:0
                                         context:nil
                                      characters:@"!"
                     charactersIgnoringModifiers:@"!"
                                       isARepeat:NO
                                         keyCode:18];
        [editor keyDown:key];
        passed = check([editor.documentText isEqualToString:@"hello!"], @"keyboard edit") &&
                 check(editor.dirty, @"keyboard dirty state") && passed;
        [editor undoEdit];
        passed = check([editor.documentText isEqualToString:@"hello"], @"keyboard undo") &&
                 check(!editor.dirty, @"keyboard undo save state") && passed;
        passed = check([editor setPluginNumber:2 property:@"editor.autocomplete.minPrefix"],
                       @"autocomplete property") && passed;
        passed = check([editor replaceRangeFromPlugin:NSMakeRange(0, 5)
                                           withString:@"helper he"], @"completion fixture") && passed;
        NSEvent* completionKey = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                                location:NSZeroPoint
                                           modifierFlags:0
                                               timestamp:0
                                            windowNumber:0
                                                 context:nil
                                              characters:@"l"
                             charactersIgnoringModifiers:@"l"
                                               isARepeat:NO
                                                 keyCode:37];
        [editor keyDown:completionKey];
        NSEvent* acceptKey = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                            location:NSZeroPoint
                                       modifierFlags:0
                                           timestamp:0
                                        windowNumber:0
                                             context:nil
                                          characters:@"\r"
                         charactersIgnoringModifiers:@"\r"
                                           isARepeat:NO
                                             keyCode:36];
        [editor keyDown:acceptKey];
        passed = check([editor.documentText isEqualToString:@"helper helper"],
                       @"native completion accepted") && passed;
        return passed ? 0 : 1;
    }
}
