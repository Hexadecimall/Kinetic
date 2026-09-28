#import "activityBar.h"
#import "editorView.h"
#import "settingsPanel.h"

#import <AppKit/AppKit.h>

@interface KineticEditorView (HistoryTest)
- (void)undoEdit;
- (void)redoEdit;
- (void)drawCaretAtRect:(NSRect)target;
- (NSRect)completionPopupRect;
- (NSRect)fixRectForLine:(NSUInteger)index diagnostic:(NSDictionary<NSString*, id>*)diagnostic;
@end

@interface KineticActivityBar (SearchTest)
- (void)controlTextDidChange:(NSNotification*)notification;
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
        for (NSDictionary* setting in kineticSettingsRows()) {
            double value = 0;
            passed = check([editor getPluginNumber:&value property:setting[@"key"]],
                           @"settings controls map to real editor properties") &&
                     passed;
        }
        editor.tabTitles = @[ @"Document" ];
        passed = check([editor setPluginNumber:1 property:@"editor.caret.smooth"],
                       @"smooth caret enabled") &&
                 passed;
        passed = check([editor setPluginNumber:120 property:@"editor.caret.duration"] &&
                           ![editor setPluginNumber:0 property:@"editor.caret.duration"] &&
                           [editor setPluginNumber:0.6 property:@"editor.caret.stretch"] &&
                           ![editor setPluginNumber:2 property:@"editor.caret.stretch"],
                       @"caret animation ranges") &&
                 passed;
        [editor setPluginNumber:1 property:@"interface.motion.enabled"];
        NSImage* caretImage = [[NSImage alloc] initWithSize:NSMakeSize(200, 100)];
        [caretImage lockFocus];
        [editor drawCaretAtRect:NSMakeRect(10, 10, 1.5, 16)];
        [editor drawCaretAtRect:NSMakeRect(90, 50, 1.5, 16)];
        passed = check(NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ||
                           [editor valueForKey:@"caretTimer"] != nil,
                       @"caret movement starts an animation") &&
                 passed;
        passed = check(NSEqualRanges(editor.pluginSelection, NSMakeRange(0, 0)),
                       @"visual caret animation leaves selection unchanged") &&
                 passed;
        [editor setPluginNumber:0 property:@"editor.caret.smooth"];
        [editor drawCaretAtRect:NSMakeRect(120, 50, 1.5, 16)];
        passed = check([editor valueForKey:@"caretTimer"] == nil,
                       @"disabling smooth caret stops the timer") &&
                 passed;
        [caretImage unlockFocus];
        [editor setActivitySection:KineticActivitySectionSettings animated:NO];
        passed = check(editor.tabTitles.count == 1, @"settings preserves document tabs") && passed;
        passed =
            check([editor closeUtilityPanelIfOpen], @"settings closes without closing document") &&
            passed;
        passed =
            check(![editor closeUtilityPanelIfOpen], @"closed panel is not reopened") && passed;
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
                       @"autocomplete property") &&
                 passed;
        passed = check([editor replaceRangeFromPlugin:NSMakeRange(0, 5) withString:@"helper he"],
                       @"completion fixture") &&
                 passed;
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
                       @"native completion accepted") &&
                 passed;
        [editor setValue:@[ @{@"label" : @"using", @"insertText" : @"using", @"detail" : @"Word"} ]
                  forKey:@"_completionItems"];
        NSRect compactPopup = [editor completionPopupRect];
        passed = check(NSWidth(compactPopup) < 200.0 && NSHeight(compactPopup) < 40.0,
                       @"one suggestion uses a compact popup") &&
                 passed;
        NSDictionary* fixDiagnostic = @{
            @"line" : @1,
            @"column" : @0,
            @"length" : @4,
            @"message" : @"Unused include",
            @"fixAvailable" : @YES,
        };
        passed = check(!NSIsEmptyRect([editor fixRectForLine:0 diagnostic:fixDiagnostic]) &&
                           NSIsEmptyRect([editor fixRectForLine:0
                                                     diagnostic:@{@"message" : @"No fix"}]),
                       @"Fix button appears only for fixable diagnostics") &&
                 passed;
        KineticEditorView* placeholder =
            [[KineticEditorView alloc] initWithFrame:NSMakeRect(0, 0, 1180, 760)
                                            contents:@""
                                             fileUrl:nil];
        placeholder.workspacePlaceholder = YES;
        [placeholder keyDown:key];
        passed = check(placeholder.documentText.length == 0 && !placeholder.dirty,
                       @"workspace placeholder does not create an untitled document") &&
                 passed;
        NSString* root = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:@"kinetic-tree-%@",
                                                                      NSUUID.UUID.UUIDString]];
        NSURL* rootUrl = [NSURL fileURLWithPath:root isDirectory:YES];
        NSURL* nestedUrl = [rootUrl URLByAppendingPathComponent:@"nested" isDirectory:YES];
        BOOL fixture = [NSFileManager.defaultManager createDirectoryAtURL:nestedUrl
                                              withIntermediateDirectories:YES
                                                               attributes:nil
                                                                    error:nil] &&
                       [@"" writeToURL:[nestedUrl URLByAppendingPathComponent:@"found.cpp"]
                            atomically:YES
                              encoding:NSUTF8StringEncoding
                                 error:nil];
        passed = check(fixture, @"tree search fixture") && passed;
        if (fixture) {
            KineticActivityBar* bar =
                [[KineticActivityBar alloc] initWithFrame:NSMakeRect(0, 0, 262, 700)];
            bar.workspaceUrl = rootUrl;
            NSTextField* query = [bar valueForKey:@"_searchField"];
            query.stringValue = @"found";
            [bar controlTextDidChange:[NSNotification
                                          notificationWithName:NSControlTextDidChangeNotification
                                                        object:query]];
            NSArray* results = [bar valueForKey:@"_treeEntries"];
            passed = check(results.count == 1, @"explorer searches nested files") && passed;
            passed = check([[[results firstObject] valueForKey:@"displayName"]
                               isEqualToString:@"nested/found.cpp"],
                           @"explorer shows result path") &&
                     passed;
        }
        [NSFileManager.defaultManager removeItemAtURL:rootUrl error:nil];
        return passed ? 0 : 1;
    }
}
