#import "editorStructure.h"

@implementation KineticStructureEdit

- (instancetype)initWithRange:(NSRange)range
                  replacement:(NSString*)replacement
                 anchorOffset:(NSUInteger)anchorOffset
                  caretOffset:(NSUInteger)caretOffset {
    self = [super init];
    if (self) {
        _range = range;
        _replacement = [replacement copy];
        _anchorOffset = anchorOffset;
        _caretOffset = caretOffset;
    }
    return self;
}

@end

namespace {

KineticStructureEdit* makeEdit(NSRange range, NSString* replacement, NSUInteger anchorOffset,
                               NSUInteger caretOffset) {
    return [[KineticStructureEdit alloc] initWithRange:range
                                           replacement:replacement
                                          anchorOffset:anchorOffset
                                           caretOffset:caretOffset];
}

NSUInteger lineStartForIndex(NSString* text, NSUInteger index) {
    if (index == 0) {
        return 0;
    }
    NSRange newline = [text rangeOfString:@"\n"
                                  options:NSBackwardsSearch
                                    range:NSMakeRange(0, index)];
    return newline.location == NSNotFound ? 0 : NSMaxRange(newline);
}

NSString* indentationOfLine(NSString* line) {
    NSUInteger length = 0;
    while (length < line.length) {
        unichar character = [line characterAtIndex:length];
        if (character != ' ' && character != '\t') {
            break;
        }
        ++length;
    }
    return [line substringToIndex:length];
}

NSString* indentationUnit(BOOL insertTabs, NSUInteger tabWidth) {
    return insertTabs ? @"\t"
                      : [@"" stringByPaddingToLength:MAX((NSUInteger)1, tabWidth)
                                          withString:@" "
                                     startingAtIndex:0];
}

NSString* firstLineOfText(NSString* text) {
    NSRange newline = [text rangeOfString:@"\n"];
    return newline.location == NSNotFound ? text : [text substringToIndex:newline.location];
}

bool isPython(NSString* fileName, NSString* text) {
    NSString* extension = fileName.lowercaseString.pathExtension;
    if ([extension isEqualToString:@"py"] || [extension isEqualToString:@"pyi"]) {
        return true;
    }
    NSString* firstLine = firstLineOfText(text).lowercaseString;
    return [firstLine hasPrefix:@"#!"] && [firstLine containsString:@"python"];
}

bool isShell(NSString* fileName, NSString* text) {
    NSString* extension = fileName.lowercaseString.pathExtension;
    if ([@[ @"sh", @"bash", @"zsh", @"fish", @"ksh", @"command" ] containsObject:extension]) {
        return true;
    }
    NSString* firstLine = firstLineOfText(text).lowercaseString;
    return [firstLine hasPrefix:@"#!"] &&
           ([firstLine containsString:@"bash"] || [firstLine containsString:@"zsh"] ||
            [firstLine containsString:@"sh"] || [firstLine containsString:@"fish"]);
}

bool shouldIncreaseIndent(NSString* trimmedPrefix, NSString* fileName, NSString* text) {
    if ([trimmedPrefix hasSuffix:@"{"] || [trimmedPrefix hasSuffix:@"["] ||
        [trimmedPrefix hasSuffix:@"("]) {
        return true;
    }
    if (isPython(fileName, text) && [trimmedPrefix hasSuffix:@":"]) {
        return true;
    }
    if (isShell(fileName, text)) {
        for (NSString* ending in @[ @"then", @"do", @"else", @"elif" ]) {
            if ([trimmedPrefix isEqualToString:ending] ||
                [trimmedPrefix hasSuffix:[@" " stringByAppendingString:ending]] ||
                [trimmedPrefix hasSuffix:[@"; " stringByAppendingString:ending]]) {
                return true;
            }
        }
    }
    return false;
}

unichar closingCharacter(unichar character) {
    switch (character) {
    case '(':
        return ')';
    case '[':
        return ']';
    case '{':
        return '}';
    case '"':
    case '\'':
    case '`':
        return character;
    default:
        return 0;
    }
}

bool isClosingCharacter(unichar character) {
    return character == ')' || character == ']' || character == '}' || character == '"' ||
           character == '\'' || character == '`';
}

bool isWordCharacter(unichar character) {
    return
        [[NSCharacterSet alphanumericCharacterSet] characterIsMember:character] || character == '_';
}

} // namespace

KineticStructureEdit* kineticNewlineEdit(NSString* text, NSRange selection, NSString* fileName,
                                         NSUInteger tabWidth, BOOL autoIndent) {
    NSUInteger lineStart = lineStartForIndex(text, selection.location);
    NSString* prefix =
        [text substringWithRange:NSMakeRange(lineStart, selection.location - lineStart)];
    return kineticNewlineEditWithTabs(text, selection, fileName, tabWidth, autoIndent,
                                      [indentationOfLine(prefix) containsString:@"\t"]);
}

KineticStructureEdit* kineticNewlineEditWithTabs(NSString* text, NSRange selection,
                                                 NSString* fileName, NSUInteger tabWidth,
                                                 BOOL autoIndent, BOOL insertTabs) {
    if (!autoIndent) {
        return makeEdit(selection, @"\n", 1, 1);
    }
    NSUInteger lineStart = lineStartForIndex(text, selection.location);
    NSString* prefix =
        [text substringWithRange:NSMakeRange(lineStart, selection.location - lineStart)];
    NSString* baseIndent = indentationOfLine(prefix);
    NSString* trimmedPrefix =
        [prefix stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    BOOL increase = shouldIncreaseIndent(trimmedPrefix, fileName, text);
    NSString* indent =
        increase ? [baseIndent stringByAppendingString:indentationUnit(insertTabs, tabWidth)]
                 : baseIndent;
    NSString* replacement = [@"\n" stringByAppendingString:indent];
    NSUInteger caretOffset = replacement.length;
    if (increase && NSMaxRange(selection) < text.length) {
        unichar last = trimmedPrefix.length > 0
                           ? [trimmedPrefix characterAtIndex:trimmedPrefix.length - 1]
                           : 0;
        unichar next = [text characterAtIndex:NSMaxRange(selection)];
        if (closingCharacter(last) == next && (last == '{' || last == '[' || last == '(')) {
            replacement = [replacement stringByAppendingFormat:@"\n%@", baseIndent];
        }
    }
    return makeEdit(selection, replacement, caretOffset, caretOffset);
}

KineticStructureEdit* kineticTabEdit(NSString* text, NSRange selection, NSUInteger tabWidth,
                                     BOOL outdent) {
    return kineticTabEditWithTabs(text, selection, tabWidth, outdent, NO);
}

KineticStructureEdit* kineticTabEditWithTabs(NSString* text, NSRange selection, NSUInteger tabWidth,
                                             BOOL outdent, BOOL insertTabs) {
    NSUInteger width = MAX((NSUInteger)1, tabWidth);
    NSUInteger lineStart = lineStartForIndex(text, selection.location);
    NSString* prefix =
        [text substringWithRange:NSMakeRange(lineStart, selection.location - lineStart)];
    if (outdent) {
        NSString* whitespace = indentationOfLine(prefix);
        if (whitespace.length == 0 || whitespace.length != prefix.length) {
            return nil;
        }
        NSUInteger removeLength = [whitespace hasSuffix:@"\t"] ? 1 : MIN(width, whitespace.length);
        NSRange range = NSMakeRange(selection.location - removeLength, removeLength);
        return makeEdit(range, @"", 0, 0);
    }
    if (insertTabs) {
        return makeEdit(selection, @"\t", 1, 1);
    }
    NSUInteger column = 0;
    for (NSUInteger index = 0; index < prefix.length; ++index) {
        column += [prefix characterAtIndex:index] == '\t' ? width - column % width : 1;
    }
    NSUInteger count = width - column % width;
    NSString* spaces = [@"" stringByPaddingToLength:count withString:@" " startingAtIndex:0];
    return makeEdit(selection, spaces, spaces.length, spaces.length);
}

KineticStructureEdit* kineticIndentBackspaceEdit(NSString* text, NSUInteger caretIndex,
                                                 NSUInteger tabWidth) {
    if (caretIndex == 0 || caretIndex > text.length) {
        return nil;
    }
    NSUInteger lineStart = lineStartForIndex(text, caretIndex);
    NSString* prefix = [text substringWithRange:NSMakeRange(lineStart, caretIndex - lineStart)];
    if (prefix.length == 0 || indentationOfLine(prefix).length != prefix.length) {
        return nil;
    }
    if ([prefix hasSuffix:@"\t"]) {
        return makeEdit(NSMakeRange(caretIndex - 1, 1), @"", 0, 0);
    }
    NSUInteger width = MAX((NSUInteger)1, tabWidth);
    NSUInteger column = 0;
    for (NSUInteger index = 0; index < prefix.length; ++index) {
        column += [prefix characterAtIndex:index] == '\t' ? width - column % width : 1;
    }
    NSUInteger target = column % width == 0 ? width : column % width;
    NSUInteger count = 0;
    while (count < target && count < prefix.length &&
           [prefix characterAtIndex:prefix.length - count - 1] == ' ') {
        ++count;
    }
    return count == 0 ? nil : makeEdit(NSMakeRange(caretIndex - count, count), @"", 0, 0);
}

KineticStructureEdit* kineticTypedStructureEdit(NSString* text, NSRange selection,
                                                NSString* character, NSUInteger tabWidth,
                                                BOOL autoPairs) {
    if (!autoPairs || character.length != 1) {
        return nil;
    }
    unichar typed = [character characterAtIndex:0];
    NSUInteger caret = selection.location;
    if (selection.length == 0 && isClosingCharacter(typed) && caret < text.length &&
        [text characterAtIndex:caret] == typed) {
        return makeEdit(NSMakeRange(caret, 0), @"", 1, 1);
    }
    if (typed == '}' && selection.length == 0) {
        NSUInteger lineStart = lineStartForIndex(text, caret);
        NSString* prefix = [text substringWithRange:NSMakeRange(lineStart, caret - lineStart)];
        if (prefix.length > 0 && indentationOfLine(prefix).length == prefix.length) {
            NSUInteger removeLength =
                [prefix hasSuffix:@"\t"] ? 1 : MIN(MAX((NSUInteger)1, tabWidth), prefix.length);
            return makeEdit(NSMakeRange(caret - removeLength, removeLength), @"}", 1, 1);
        }
    }
    unichar closing = closingCharacter(typed);
    if (closing == 0) {
        return nil;
    }
    BOOL quote = typed == '"' || typed == '\'' || typed == '`';
    if (quote && selection.length == 0) {
        if (typed == '\'' && caret > 0 && isWordCharacter([text characterAtIndex:caret - 1])) {
            return nil;
        }
        if (caret < text.length && isWordCharacter([text characterAtIndex:caret])) {
            return nil;
        }
    }
    NSString* selected = [text substringWithRange:selection];
    NSString* replacement = [NSString stringWithFormat:@"%C%@%C", typed, selected, closing];
    return makeEdit(selection, replacement, 1, 1 + selected.length);
}

KineticStructureEdit* kineticPairedBackspaceEdit(NSString* text, NSUInteger caretIndex,
                                                 BOOL autoPairs) {
    if (!autoPairs || caretIndex == 0 || caretIndex >= text.length) {
        return nil;
    }
    unichar opening = [text characterAtIndex:caretIndex - 1];
    if (closingCharacter(opening) != [text characterAtIndex:caretIndex]) {
        return nil;
    }
    return makeEdit(NSMakeRange(caretIndex - 1, 2), @"", 0, 0);
}
