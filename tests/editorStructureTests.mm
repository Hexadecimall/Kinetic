#import <Foundation/Foundation.h>

#import "editorStructure.h"

static void require(BOOL condition, NSString* message) {
    if (!condition) {
        NSLog(@"Structure test failed: %@", message);
        exit(1);
    }
}

static NSString* applyEdit(NSString* original, KineticStructureEdit* edit) {
    NSMutableString* result = [original mutableCopy];
    [result replaceCharactersInRange:edit.range withString:edit.replacement];
    return result;
}

int main() {
    @autoreleasepool {
        KineticStructureEdit* edit = kineticNewlineEdit(@"    echo hello", NSMakeRange(14, 0),
                                                       @"run.sh", 4, YES);
        require([applyEdit(@"    echo hello", edit) isEqualToString:@"    echo hello\n    "],
                @"newline preserves spaces");
        edit = kineticNewlineEdit(@"\tif true; then", NSMakeRange(14, 0), @"run.sh", 4, YES);
        require([applyEdit(@"\tif true; then", edit) isEqualToString:@"\tif true; then\n\t\t"],
                @"shell block preserves tabs and adds one level");
        edit = kineticNewlineEdit(@"if ready:", NSMakeRange(9, 0), @"main.py", 4, YES);
        require([applyEdit(@"if ready:", edit) isEqualToString:@"if ready:\n    "],
                @"Python colon increases indentation");
        edit = kineticNewlineEdit(@"{}", NSMakeRange(1, 0), @"main.rs", 4, YES);
        require([applyEdit(@"{}", edit) isEqualToString:@"{\n    \n}"],
                @"newline inside pair splits block");
        require(edit.caretOffset == 5, @"caret stays inside block");
        edit = kineticNewlineEdit(@"{", NSMakeRange(1, 0), @"main.rs", 4, NO);
        require([applyEdit(@"{", edit) isEqualToString:@"{\n"], @"auto indent can be disabled");

        edit = kineticTabEdit(@"  abc", NSMakeRange(2, 0), 4, NO);
        require([applyEdit(@"  abc", edit) isEqualToString:@"    abc"],
                @"Tab advances to next tab stop");
        edit = kineticTabEdit(@"    abc", NSMakeRange(4, 0), 4, YES);
        require([applyEdit(@"    abc", edit) isEqualToString:@"abc"],
                @"Shift-Tab removes one indentation level");
        edit = kineticTabEditWithTabs(@"  abc", NSMakeRange(2, 0), 4, NO, YES);
        require([applyEdit(@"  abc", edit) isEqualToString:@"  \tabc"],
                @"Tab-character setting inserts a literal tab");
        edit = kineticNewlineEditWithTabs(@"if ready:", NSMakeRange(9, 0), @"main.py", 4,
                                          YES, YES);
        require([applyEdit(@"if ready:", edit) isEqualToString:@"if ready:\n\t"],
                @"Auto indent follows the tab-character setting");
        edit = kineticIndentBackspaceEdit(@"        value", 8, 4);
        require([applyEdit(@"        value", edit) isEqualToString:@"    value"],
                @"Backspace removes one indentation unit");
        edit = kineticIndentBackspaceEdit(@"   value", 3, 4);
        require([applyEdit(@"   value", edit) isEqualToString:@"value"],
                @"Backspace removes partial indentation");
        require(kineticIndentBackspaceEdit(@"    value", 5, 4) == nil,
                @"Backspace inside code is a normal character edit");
        require(kineticIndentNavigationIndex(@"        value", 8, 4, NO) == 4 &&
                    kineticIndentNavigationIndex(@"        value", 4, 4, NO) == 0 &&
                    kineticIndentNavigationIndex(@"        value", 0, 4, YES) == 4,
                @"arrow navigation moves by indentation units");
        require(kineticIndentSnapIndex(@"        value", 6, 4) == 4 &&
                    kineticIndentSnapIndex(@"        value", 7, 4) == 8,
                @"mouse placement snaps to an indentation stop");
        require(kineticIndentNavigationIndex(@"    code name", 9, 4, NO) == NSNotFound,
                @"ordinary spaces remain individually navigable");

        edit = kineticTypedStructureEdit(@"", NSMakeRange(0, 0), @"{", 4, YES);
        require([applyEdit(@"", edit) isEqualToString:@"{}"] && edit.caretOffset == 1,
                @"opening brace auto-pairs");
        edit = kineticTypedStructureEdit(@"{}", NSMakeRange(1, 0), @"}", 4, YES);
        require(edit.replacement.length == 0 && edit.caretOffset == 1,
                @"typing existing closer skips over it");
        edit = kineticTypedStructureEdit(@"name", NSMakeRange(0, 4), @"(", 4, YES);
        require([applyEdit(@"name", edit) isEqualToString:@"(name)"] &&
                    edit.anchorOffset == 1 && edit.caretOffset == 5,
                @"selection is wrapped and retained");
        require(kineticTypedStructureEdit(@"don", NSMakeRange(3, 0), @"'", 4, YES) == nil,
                @"apostrophe inside a word is not paired");
        edit = kineticTypedStructureEdit(@"    ", NSMakeRange(4, 0), @"}", 4, YES);
        require([applyEdit(@"    ", edit) isEqualToString:@"}"],
                @"closing brace outdents blank line");
        edit = kineticPairedBackspaceEdit(@"{}", 1, YES);
        require([applyEdit(@"{}", edit) isEqualToString:@""],
                @"Backspace removes an empty pair");
        require(kineticPairedBackspaceEdit(@"{}", 1, NO) == nil,
                @"auto pairing can be disabled");
    }
    return 0;
}
