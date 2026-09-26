#import "editorView.h"

#import "activityBar.h"

namespace {

constexpr CGFloat kFirstLineY = 84.0;
constexpr CGFloat kTextOriginX = 92.0;
constexpr CGFloat kContextMenuWidth = 196.0;
constexpr CGFloat kContextMenuRowHeight = 27.0;
constexpr CGFloat kContextMenuPadding = 8.0;
constexpr CGFloat kContextMenuSeparatorHeight = 7.0;

enum class EditorMenuCommand : NSInteger {
    undo,
    redo,
    cut,
    copy,
    paste,
    selectAll,
};

NSColor* editorColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha = 1.0) {
    return [NSColor colorWithSRGBRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:alpha];
}

} // namespace

@interface KineticEditorView () <KineticActivityBarDelegate> {
    NSMutableString* _text;
    NSString* _savedText;
    NSMutableArray<NSDictionary*>* _undoStack;
    NSMutableArray<NSDictionary*>* _redoStack;
    NSUInteger _caretIndex;
    NSUInteger _selectionAnchor;
    NSTrackingArea* _trackingArea;
    BOOL _closeHovered;
    BOOL _draggingSelection;
    BOOL _contextMenuVisible;
    NSInteger _contextMenuHoveredIndex;
    NSRect _contextMenuFrame;
    KineticActivityBar* _activityBar;
    BOOL _dirty;
    NSURL* _fileUrl;
    CGFloat _verticalScroll;
    CGFloat _horizontalScroll;
    CGFloat _fontSize;
    CGFloat _lineHeight;
    BOOL _showLineNumbers;
    BOOL _showScrollIndicators;
    BOOL _naturalScrolling;
    BOOL _settingsVisible;
    NSInteger _settingsHoveredControl;
    NSURL* _workspaceUrl;
}
@end

@implementation KineticEditorView

- (instancetype)initWithFrame:(NSRect)frameRect {
    return [self initWithFrame:frameRect contents:@"" fileUrl:nil];
}

- (instancetype)initWithFrame:(NSRect)frameRect
                     contents:(NSString*)contents
                      fileUrl:(NSURL*)fileUrl {
    self = [super initWithFrame:frameRect];
    if (self) {
        _text = [[NSMutableString alloc] initWithString:contents ?: @""];
        _savedText = [_text copy];
        _undoStack = [NSMutableArray array];
        _redoStack = [NSMutableArray array];
        _caretIndex = 0;
        _selectionAnchor = 0;
        _closeHovered = NO;
        _draggingSelection = NO;
        _contextMenuVisible = NO;
        _contextMenuHoveredIndex = -1;
        _contextMenuFrame = NSZeroRect;
        _dirty = NO;
        _fileUrl = fileUrl;
        _verticalScroll = 0.0;
        _horizontalScroll = 0.0;
        _fontSize = 13.0;
        _lineHeight = 20.0;
        _showLineNumbers = YES;
        _showScrollIndicators = YES;
        _naturalScrolling = YES;
        _settingsVisible = NO;
        _settingsHoveredControl = -1;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _activityBar = [[KineticActivityBar alloc]
            initWithFrame:NSMakeRect(0.0, 68.0, KineticActivityBar.railWidth,
                                     MAX(0.0, NSHeight(frameRect) - 68.0))];
        _activityBar.delegate = self;
        _activityBar.documentTitle = fileUrl.lastPathComponent ?: @"Untitled-1";
        [self addSubview:_activityBar];
    }
    return self;
}

- (NSString*)documentText {
    return [_text copy];
}

- (NSURL*)fileUrl {
    return _fileUrl;
}

- (void)setFileUrl:(NSURL*)fileUrl {
    _fileUrl = fileUrl;
    _activityBar.documentTitle = fileUrl.lastPathComponent ?: @"Untitled-1";
    self.needsDisplay = YES;
}

- (NSURL*)workspaceUrl {
    return _workspaceUrl;
}

- (void)setWorkspaceUrl:(NSURL*)workspaceUrl {
    _workspaceUrl = workspaceUrl;
    _activityBar.workspaceUrl = workspaceUrl;
}

- (BOOL)dirty {
    return _dirty;
}

- (void)markSaved {
    _savedText = [_text copy];
    _dirty = NO;
    self.needsDisplay = YES;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return NO;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (NSRect)closeRect {
    return NSMakeRect(100.0, 41.0, 20.0, 20.0);
}

- (NSDictionary<NSAttributedStringKey, id>*)editorTextAttributes {
    return @{
        NSFontAttributeName : [NSFont monospacedSystemFontOfSize:_fontSize
                                                          weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : editorColor(226, 233, 242),
    };
}

- (NSArray<NSString*>*)documentLines {
    return [_text componentsSeparatedByString:@"\n"];
}

- (NSRange)selectionRange {
    NSUInteger start = MIN(_selectionAnchor, _caretIndex);
    NSUInteger end = MAX(_selectionAnchor, _caretIndex);
    return NSMakeRange(start, end - start);
}

- (void)updateDirtyState {
    _dirty = ![_text isEqualToString:_savedText];
}

- (NSDictionary*)editorState {
    return @{
        @"text" : [_text copy],
        @"caret" : @(_caretIndex),
        @"anchor" : @(_selectionAnchor),
    };
}

- (void)restoreEditorState:(NSDictionary*)state {
    [_text setString:state[@"text"]];
    _caretIndex = [state[@"caret"] unsignedIntegerValue];
    _selectionAnchor = [state[@"anchor"] unsignedIntegerValue];
    [self updateDirtyState];
    [self ensureCaretVisible];
    self.needsDisplay = YES;
}

- (void)recordUndoState {
    [_undoStack addObject:[self editorState]];
    if (_undoStack.count > 256) {
        [_undoStack removeObjectAtIndex:0];
    }
    [_redoStack removeAllObjects];
}

- (void)undoEdit {
    NSDictionary* state = _undoStack.lastObject;
    if (state == nil) {
        return;
    }
    [_redoStack addObject:[self editorState]];
    [_undoStack removeLastObject];
    [self restoreEditorState:state];
}

- (void)redoEdit {
    NSDictionary* state = _redoStack.lastObject;
    if (state == nil) {
        return;
    }
    [_undoStack addObject:[self editorState]];
    [_redoStack removeLastObject];
    [self restoreEditorState:state];
}

- (BOOL)deleteSelection {
    NSRange selection = [self selectionRange];
    if (selection.length == 0) {
        return NO;
    }
    [_text deleteCharactersInRange:selection];
    _caretIndex = selection.location;
    _selectionAnchor = _caretIndex;
    [self updateDirtyState];
    return YES;
}

- (void)replaceSelectionWithString:(NSString*)replacement {
    [self recordUndoState];
    [self deleteSelection];
    [_text insertString:replacement atIndex:_caretIndex];
    _caretIndex += replacement.length;
    _selectionAnchor = _caretIndex;
    [self updateDirtyState];
}

- (void)copySelection {
    NSRange selection = [self selectionRange];
    if (selection.length == 0) {
        return;
    }
    NSPasteboard* pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:[_text substringWithRange:selection] forType:NSPasteboardTypeString];
}

- (void)cutSelection {
    if ([self selectionRange].length == 0) {
        return;
    }
    [self copySelection];
    [self recordUndoState];
    [self deleteSelection];
}

- (void)pasteText {
    NSString* pastedText = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
    if (pastedText == nil) {
        return;
    }
    [self replaceSelectionWithString:pastedText];
}

- (void)selectAllText {
    _selectionAnchor = 0;
    _caretIndex = _text.length;
    [self ensureCaretVisible];
    self.needsDisplay = YES;
}

- (NSUInteger)previousWordIndexFromIndex:(NSUInteger)index {
    NSCharacterSet* whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSCharacterSet* wordCharacters = [NSCharacterSet alphanumericCharacterSet];
    NSUInteger cursor = index;
    while (cursor > 0 && [whitespace characterIsMember:[_text characterAtIndex:cursor - 1]]) {
        --cursor;
    }
    if (cursor == 0) {
        return 0;
    }
    unichar character = [_text characterAtIndex:cursor - 1];
    BOOL isWord = [wordCharacters characterIsMember:character] || character == '_';
    while (cursor > 0) {
        character = [_text characterAtIndex:cursor - 1];
        BOOL candidateIsWord = [wordCharacters characterIsMember:character] || character == '_';
        if ([whitespace characterIsMember:character] || candidateIsWord != isWord) {
            break;
        }
        --cursor;
    }
    return cursor;
}

- (NSUInteger)nextWordIndexFromIndex:(NSUInteger)index {
    NSCharacterSet* whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSCharacterSet* wordCharacters = [NSCharacterSet alphanumericCharacterSet];
    NSUInteger cursor = index;
    while (cursor < _text.length && [whitespace
                                        characterIsMember:[_text characterAtIndex:cursor]]) {
        ++cursor;
    }
    if (cursor == _text.length) {
        return cursor;
    }
    unichar character = [_text characterAtIndex:cursor];
    BOOL isWord = [wordCharacters characterIsMember:character] || character == '_';
    while (cursor < _text.length) {
        character = [_text characterAtIndex:cursor];
        BOOL candidateIsWord = [wordCharacters characterIsMember:character] || character == '_';
        if ([whitespace characterIsMember:character] || candidateIsWord != isWord) {
            break;
        }
        ++cursor;
    }
    return cursor;
}

- (NSUInteger)lineStartIndexFromIndex:(NSUInteger)index {
    NSRange searchRange = NSMakeRange(0, index);
    NSRange newline = [_text rangeOfString:@"\n" options:NSBackwardsSearch range:searchRange];
    return newline.location == NSNotFound ? 0 : NSMaxRange(newline);
}

- (NSUInteger)lineEndIndexFromIndex:(NSUInteger)index {
    NSRange searchRange = NSMakeRange(index, _text.length - index);
    NSRange newline = [_text rangeOfString:@"\n" options:0 range:searchRange];
    return newline.location == NSNotFound ? _text.length : newline.location;
}

- (NSUInteger)textIndexForPoint:(NSPoint)point {
    NSArray<NSString*>* lines = [self documentLines];
    NSInteger lineIndex = (NSInteger)floor((point.y - kFirstLineY + _verticalScroll) / _lineHeight);
    lineIndex = MIN((NSInteger)lines.count - 1, MAX(0, lineIndex));

    NSUInteger lineStart = 0;
    for (NSInteger index = 0; index < lineIndex; ++index) {
        lineStart += lines[(NSUInteger)index].length + 1;
    }

    NSString* line = lines[(NSUInteger)lineIndex];
    CGFloat targetX = point.x - kTextOriginX + _horizontalScroll;
    if (targetX <= 0.0 || line.length == 0) {
        return lineStart;
    }

    NSDictionary* attributes = [self editorTextAttributes];
    __block CGFloat consumedWidth = 0.0;
    __block NSUInteger column = line.length;
    [line enumerateSubstringsInRange:NSMakeRange(0, line.length)
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString* substring, NSRange substringRange,
                                       NSRange enclosingRange, BOOL* stop) {
                            (void)enclosingRange;
                            CGFloat glyphWidth = [substring sizeWithAttributes:attributes].width;
                            if (targetX < consumedWidth + glyphWidth * 0.5) {
                                column = substringRange.location;
                                *stop = YES;
                                return;
                            }
                            consumedWidth += glyphWidth;
                          }];
    return lineStart + column;
}

- (CGFloat)maximumVerticalScroll {
    CGFloat viewportHeight = MAX(1.0, NSHeight(self.bounds) - kFirstLineY - 12.0);
    return MAX(0.0, [self documentLines].count * _lineHeight - viewportHeight);
}

- (CGFloat)maximumHorizontalScroll {
    NSDictionary* attributes = [self editorTextAttributes];
    CGFloat widestLine = 0.0;
    for (NSString* line in [self documentLines]) {
        widestLine = MAX(widestLine, [line sizeWithAttributes:attributes].width);
    }
    return MAX(0.0, widestLine - MAX(1.0, NSWidth(self.bounds) - 116.0));
}

- (void)clampScroll {
    _verticalScroll = MIN([self maximumVerticalScroll], MAX(0.0, _verticalScroll));
    _horizontalScroll = MIN([self maximumHorizontalScroll], MAX(0.0, _horizontalScroll));
}

- (void)getCaretLine:(NSUInteger*)lineOut column:(NSUInteger*)columnOut {
    NSString* beforeCaret = [_text substringToIndex:_caretIndex];
    NSArray<NSString*>* lines = [beforeCaret componentsSeparatedByString:@"\n"];
    *lineOut = lines.count - 1;
    *columnOut = lines.lastObject.length;
}

- (void)ensureCaretVisible {
    NSUInteger line = 0;
    NSUInteger column = 0;
    [self getCaretLine:&line column:&column];
    CGFloat caretY = line * _lineHeight;
    CGFloat viewportHeight = MAX(1.0, NSHeight(self.bounds) - kFirstLineY - 12.0);
    if (caretY < _verticalScroll) {
        _verticalScroll = caretY;
    } else if (caretY + _lineHeight > _verticalScroll + viewportHeight) {
        _verticalScroll = caretY + _lineHeight - viewportHeight;
    }

    NSString* lineText = [self documentLines][line];
    NSString* beforeCaret = [lineText substringToIndex:MIN(column, lineText.length)];
    CGFloat caretX = [beforeCaret sizeWithAttributes:[self editorTextAttributes]].width;
    CGFloat viewportWidth = MAX(1.0, NSWidth(self.bounds) - 116.0);
    if (caretX < _horizontalScroll) {
        _horizontalScroll = caretX;
    } else if (caretX + 10.0 > _horizontalScroll + viewportWidth) {
        _horizontalScroll = caretX + 10.0 - viewportWidth;
    }
    [self clampScroll];
}

- (void)moveCaretVertically:(NSInteger)lineDelta {
    NSArray<NSString*>* lines = [self documentLines];
    NSUInteger line = 0;
    NSUInteger column = 0;
    [self getCaretLine:&line column:&column];
    NSInteger targetLine = MIN((NSInteger)lines.count - 1, MAX(0, (NSInteger)line + lineDelta));
    NSUInteger targetColumn = MIN(column, lines[(NSUInteger)targetLine].length);
    NSUInteger targetIndex = targetColumn;
    for (NSInteger index = 0; index < targetLine; ++index) {
        targetIndex += lines[(NSUInteger)index].length + 1;
    }
    _caretIndex = targetIndex;
}

- (NSArray<NSString*>*)contextMenuTitles {
    return @[ @"Undo", @"Redo", @"Cut", @"Copy", @"Paste", @"Select All" ];
}

- (NSArray<NSString*>*)contextMenuShortcuts {
    return @[ @"⌘Z", @"⇧⌘Z", @"⌘X", @"⌘C", @"⌘V", @"⌘A" ];
}

- (CGFloat)contextMenuRowOffset:(NSInteger)index {
    CGFloat offset = kContextMenuPadding + index * kContextMenuRowHeight;
    if (index >= 2) {
        offset += kContextMenuSeparatorHeight;
    }
    if (index >= 5) {
        offset += kContextMenuSeparatorHeight;
    }
    return offset;
}

- (NSRect)contextMenuRowRect:(NSInteger)index {
    return NSMakeRect(NSMinX(_contextMenuFrame) + 5.0,
                      NSMinY(_contextMenuFrame) + [self contextMenuRowOffset:index],
                      NSWidth(_contextMenuFrame) - 10.0, kContextMenuRowHeight);
}

- (NSInteger)contextMenuIndexAtPoint:(NSPoint)point {
    if (!_contextMenuVisible || !NSPointInRect(point, _contextMenuFrame)) {
        return -1;
    }
    for (NSInteger index = 0; index < (NSInteger)[self contextMenuTitles].count; ++index) {
        if (NSPointInRect(point, [self contextMenuRowRect:index])) {
            return index;
        }
    }
    return -1;
}

- (BOOL)contextMenuItemEnabled:(NSInteger)index {
    switch ((EditorMenuCommand)index) {
    case EditorMenuCommand::undo:
        return _undoStack.count > 0;
    case EditorMenuCommand::redo:
        return _redoStack.count > 0;
    case EditorMenuCommand::cut:
    case EditorMenuCommand::copy:
        return [self selectionRange].length > 0;
    case EditorMenuCommand::paste:
        return [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString] != nil;
    case EditorMenuCommand::selectAll:
        return _text.length > 0;
    }
    return NO;
}

- (void)performContextMenuItem:(NSInteger)index {
    if (![self contextMenuItemEnabled:index]) {
        return;
    }
    switch ((EditorMenuCommand)index) {
    case EditorMenuCommand::undo:
        [self undoEdit];
        break;
    case EditorMenuCommand::redo:
        [self redoEdit];
        break;
    case EditorMenuCommand::cut:
        [self cutSelection];
        break;
    case EditorMenuCommand::copy:
        [self copySelection];
        break;
    case EditorMenuCommand::paste:
        [self pasteText];
        break;
    case EditorMenuCommand::selectAll:
        [self selectAllText];
        break;
    }
    [self ensureCaretVisible];
    self.needsDisplay = YES;
}

- (void)showContextMenuAtPoint:(NSPoint)point {
    CGFloat menuHeight =
        kContextMenuPadding * 2.0 + kContextMenuRowHeight * 6.0 + kContextMenuSeparatorHeight * 2.0;
    CGFloat x = MIN(point.x, NSWidth(self.bounds) - kContextMenuWidth - 8.0);
    CGFloat y = MIN(point.y, NSHeight(self.bounds) - menuHeight - 8.0);
    x = MAX(8.0, x);
    y = MAX(72.0, y);
    _contextMenuFrame = NSMakeRect(x, y, kContextMenuWidth, menuHeight);
    _contextMenuHoveredIndex = -1;
    _contextMenuVisible = YES;
    [self.window invalidateCursorRectsForView:self];
    self.needsDisplay = YES;
}

- (void)hideContextMenu {
    if (!_contextMenuVisible) {
        return;
    }
    _contextMenuVisible = NO;
    _contextMenuHoveredIndex = -1;
    [self.window invalidateCursorRectsForView:self];
    self.needsDisplay = YES;
}

- (void)drawContextMenu {
    if (!_contextMenuVisible) {
        return;
    }

    NSShadow* shadow = [[NSShadow alloc] init];
    shadow.shadowColor = editorColor(5, 9, 16, 0.55);
    shadow.shadowBlurRadius = 18.0;
    shadow.shadowOffset = NSMakeSize(0.0, 6.0);
    [NSGraphicsContext saveGraphicsState];
    [shadow set];
    [editorColor(35, 43, 55, 0.98) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:_contextMenuFrame xRadius:7.0 yRadius:7.0] fill];
    [NSGraphicsContext restoreGraphicsState];

    [editorColor(75, 90, 111, 0.75) setStroke];
    NSBezierPath* outline = [NSBezierPath bezierPathWithRoundedRect:_contextMenuFrame
                                                            xRadius:7.0
                                                            yRadius:7.0];
    outline.lineWidth = 1.0;
    [outline stroke];

    NSArray<NSString*>* titles = [self contextMenuTitles];
    NSArray<NSString*>* shortcuts = [self contextMenuShortcuts];
    NSDictionary* titleAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : editorColor(226, 233, 242),
    };
    NSDictionary* shortcutAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : editorColor(139, 155, 177),
    };
    NSDictionary* disabledAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : editorColor(107, 119, 137),
    };

    for (NSInteger index = 0; index < (NSInteger)titles.count; ++index) {
        NSRect rowRect = [self contextMenuRowRect:index];
        BOOL enabled = [self contextMenuItemEnabled:index];
        if (enabled && index == _contextMenuHoveredIndex) {
            [editorColor(77, 141, 255, 0.2) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:rowRect xRadius:4.0 yRadius:4.0] fill];
        }
        NSDictionary* attributes = enabled ? titleAttributes : disabledAttributes;
        [titles[(NSUInteger)index]
               drawAtPoint:NSMakePoint(NSMinX(rowRect) + 8.0, NSMinY(rowRect) + 5.5)
            withAttributes:attributes];
        NSSize shortcutSize = [shortcuts[(NSUInteger)index] sizeWithAttributes:shortcutAttributes];
        [shortcuts[(NSUInteger)index]
               drawAtPoint:NSMakePoint(NSMaxX(rowRect) - shortcutSize.width - 8.0,
                                       NSMinY(rowRect) + 6.0)
            withAttributes:enabled ? shortcutAttributes : disabledAttributes];
    }

    [editorColor(75, 90, 111, 0.58) setStroke];
    NSInteger separatorIndexes[] = {2, 5};
    for (NSInteger nextIndex : separatorIndexes) {
        CGFloat separatorY = NSMinY(_contextMenuFrame) + [self contextMenuRowOffset:nextIndex] -
                             kContextMenuSeparatorHeight * 0.5;
        NSBezierPath* separator = [NSBezierPath bezierPath];
        separator.lineWidth = 1.0;
        [separator moveToPoint:NSMakePoint(NSMinX(_contextMenuFrame) + 12.0, separatorY)];
        [separator lineToPoint:NSMakePoint(NSMaxX(_contextMenuFrame) - 12.0, separatorY)];
        [separator stroke];
    }
}

- (NSRect)settingsRowRect:(NSInteger)index {
    CGFloat x = KineticActivityBar.railWidth + 42.0;
    CGFloat width = MIN(620.0, NSWidth(self.bounds) - x - 42.0);
    return NSMakeRect(x, 154.0 + index * 56.0, MAX(320.0, width), 44.0);
}

- (NSRect)settingsMinusRectForRow:(NSInteger)row {
    NSRect rowRect = [self settingsRowRect:row];
    return NSMakeRect(NSMaxX(rowRect) - 112.0, NSMinY(rowRect) + 8.0, 28.0, 28.0);
}

- (NSRect)settingsPlusRectForRow:(NSInteger)row {
    NSRect rowRect = [self settingsRowRect:row];
    return NSMakeRect(NSMaxX(rowRect) - 34.0, NSMinY(rowRect) + 8.0, 28.0, 28.0);
}

- (NSRect)settingsToggleRectForRow:(NSInteger)row {
    NSRect rowRect = [self settingsRowRect:row];
    return NSMakeRect(NSMaxX(rowRect) - 48.0, NSMinY(rowRect) + 11.0, 38.0, 22.0);
}

- (NSInteger)settingsControlAtPoint:(NSPoint)point {
    if (NSPointInRect(point, [self settingsMinusRectForRow:0])) {
        return 0;
    }
    if (NSPointInRect(point, [self settingsPlusRectForRow:0])) {
        return 1;
    }
    if (NSPointInRect(point, [self settingsMinusRectForRow:1])) {
        return 2;
    }
    if (NSPointInRect(point, [self settingsPlusRectForRow:1])) {
        return 3;
    }
    for (NSInteger row = 2; row <= 4; ++row) {
        if (NSPointInRect(point, [self settingsToggleRectForRow:row])) {
            return row + 2;
        }
    }
    return -1;
}

- (void)applySettingsControl:(NSInteger)control {
    switch (control) {
    case 0:
        _fontSize = MAX(8.0, _fontSize - 1.0);
        break;
    case 1:
        _fontSize = MIN(28.0, _fontSize + 1.0);
        break;
    case 2:
        _lineHeight = MAX(14.0, _lineHeight - 1.0);
        break;
    case 3:
        _lineHeight = MIN(40.0, _lineHeight + 1.0);
        break;
    case 4:
        _showLineNumbers = !_showLineNumbers;
        break;
    case 5:
        _showScrollIndicators = !_showScrollIndicators;
        break;
    case 6:
        _naturalScrolling = !_naturalScrolling;
        break;
    default:
        return;
    }
    [self clampScroll];
    self.needsDisplay = YES;
}

- (void)drawSettingsToggle:(BOOL)enabled inRect:(NSRect)rect hovered:(BOOL)hovered {
    NSColor* fill = enabled ? editorColor(77, 141, 255, hovered ? 0.96 : 0.82)
                            : editorColor(74, 87, 105, hovered ? 0.95 : 0.72);
    [fill setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect
                                     xRadius:NSHeight(rect) * 0.5
                                     yRadius:NSHeight(rect) * 0.5] fill];
    CGFloat knobX = enabled ? NSMaxX(rect) - 17.0 : NSMinX(rect) + 5.0;
    [editorColor(235, 240, 247) setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(knobX, NSMinY(rect) + 5.0, 12.0, 12.0)]
        fill];
}

- (void)drawSettingsStepButton:(NSRect)rect title:(NSString*)title hovered:(BOOL)hovered {
    [editorColor(62, 75, 93, hovered ? 0.98 : 0.78) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:4.0 yRadius:4.0] fill];
    NSDictionary* attributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:15.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : editorColor(220, 229, 241),
    };
    NSSize size = [title sizeWithAttributes:attributes];
    [title drawAtPoint:NSMakePoint(NSMidX(rect) - size.width * 0.5,
                                   NSMidY(rect) - size.height * 0.5)
        withAttributes:attributes];
}

- (void)drawSettingsPage {
    CGFloat x = KineticActivityBar.railWidth + 42.0;
    NSDictionary* titleAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:24.0 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName : editorColor(235, 240, 247),
    };
    NSDictionary* subtitleAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : editorColor(139, 155, 177),
    };
    NSDictionary* rowTitleAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName : editorColor(220, 229, 241),
    };
    NSDictionary* rowDetailAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : editorColor(132, 146, 166),
    };

    [@"Settings" drawAtPoint:NSMakePoint(x, 92.0) withAttributes:titleAttributes];
    [@"Changes apply immediately to this editor." drawAtPoint:NSMakePoint(x, 124.0)
                                               withAttributes:subtitleAttributes];

    NSArray<NSString*>* titles = @[
        @"Font Size", @"Line Height", @"Line Numbers", @"Scroll Indicators", @"Natural Scrolling"
    ];
    NSArray<NSString*>* details = @[
        @"Editor text size", @"Distance between text rows", @"Show the editor gutter numbers",
        @"Show horizontal and vertical position markers", @"Match trackpad content direction"
    ];
    for (NSInteger row = 0; row < (NSInteger)titles.count; ++row) {
        NSRect rowRect = [self settingsRowRect:row];
        [editorColor(50, 61, 76, 0.72) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:rowRect xRadius:5.0 yRadius:5.0] fill];
        [titles[(NSUInteger)row]
               drawAtPoint:NSMakePoint(NSMinX(rowRect) + 13.0, NSMinY(rowRect) + 7.0)
            withAttributes:rowTitleAttributes];
        [details[(NSUInteger)row]
               drawAtPoint:NSMakePoint(NSMinX(rowRect) + 13.0, NSMinY(rowRect) + 25.0)
            withAttributes:rowDetailAttributes];
        if (row < 2) {
            [self drawSettingsStepButton:[self settingsMinusRectForRow:row]
                                   title:@"−"
                                 hovered:_settingsHoveredControl == row * 2];
            [self drawSettingsStepButton:[self settingsPlusRectForRow:row]
                                   title:@"+"
                                 hovered:_settingsHoveredControl == row * 2 + 1];
            NSString* value =
                [NSString stringWithFormat:@"%.0f", row == 0 ? _fontSize : _lineHeight];
            [value drawInRect:NSMakeRect(NSMaxX(rowRect) - 82.0, NSMinY(rowRect) + 13.0, 46.0, 18.0)
                withAttributes:rowTitleAttributes];
        } else {
            BOOL enabled = row == 2 ? _showLineNumbers
                                    : (row == 3 ? _showScrollIndicators : _naturalScrolling);
            [self drawSettingsToggle:enabled
                              inRect:[self settingsToggleRectForRow:row]
                             hovered:_settingsHoveredControl == row + 2];
        }
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [editorColor(47, 57, 71, 0.9) setFill];
    NSRectFill(self.bounds);

    [editorColor(42, 51, 64, 0.9) setFill];
    NSRectFill(NSMakeRect(0.0, 34.0, NSWidth(self.bounds), 34.0));
    [editorColor(47, 57, 71, 0.9) setFill];
    NSRect tabRect = NSMakeRect(0.0, 34.0, 126.0, 34.0);
    NSRectFill(tabRect);
    [editorColor(77, 141, 255) setFill];
    NSRectFill(NSMakeRect(0.0, 66.0, NSWidth(tabRect), 2.0));

    NSDictionary* tabAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName : editorColor(220, 228, 239),
    };
    NSString* tabTitle =
        _settingsVisible ? @"Settings" : (_fileUrl.lastPathComponent ?: @"Untitled-1");
    [tabTitle drawAtPoint:NSMakePoint(12.0, 43.0) withAttributes:tabAttributes];

    NSRect closeRect = [self closeRect];
    if (_closeHovered) {
        [editorColor(77, 141, 255, 0.18) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:closeRect xRadius:3.0 yRadius:3.0] fill];
    }
    if (_dirty && !_closeHovered) {
        [editorColor(255, 145, 92) setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMidX(closeRect) - 3.0,
                                                           NSMidY(closeRect) - 3.0, 6.0, 6.0)]
            fill];
    } else {
        NSBezierPath* closeIcon = [NSBezierPath bezierPath];
        closeIcon.lineWidth = 1.15;
        closeIcon.lineCapStyle = NSLineCapStyleRound;
        [closeIcon moveToPoint:NSMakePoint(NSMidX(closeRect) - 3.0, NSMidY(closeRect) - 3.0)];
        [closeIcon lineToPoint:NSMakePoint(NSMidX(closeRect) + 3.0, NSMidY(closeRect) + 3.0)];
        [closeIcon moveToPoint:NSMakePoint(NSMidX(closeRect) + 3.0, NSMidY(closeRect) - 3.0)];
        [closeIcon lineToPoint:NSMakePoint(NSMidX(closeRect) - 3.0, NSMidY(closeRect) + 3.0)];
        [editorColor(171, 184, 201) setStroke];
        [closeIcon stroke];
    }

    if (_settingsVisible) {
        [self drawSettingsPage];
        return;
    }

    [self clampScroll];
    NSDictionary* textAttributes = [self editorTextAttributes];
    NSDictionary* lineNumberAttributes = @{
        NSFontAttributeName : [NSFont monospacedDigitSystemFontOfSize:12.0
                                                               weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : editorColor(118, 132, 151),
    };

    NSArray<NSString*>* lines = [self documentLines];
    NSRect contentRect = NSMakeRect(KineticActivityBar.railWidth, 68.0,
                                    NSWidth(self.bounds) - KineticActivityBar.railWidth,
                                    NSHeight(self.bounds) - 68.0);
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:contentRect] addClip];
    NSUInteger lineStart = 0;
    for (NSUInteger index = 0; index < lines.count; ++index) {
        NSString* line = lines[index];
        NSUInteger currentLineStart = lineStart;
        lineStart += line.length + (index + 1 < lines.count ? 1 : 0);
        CGFloat y = kFirstLineY + index * _lineHeight - _verticalScroll;
        if (y + _lineHeight < NSMinY(contentRect) || y > NSMaxY(contentRect)) {
            continue;
        }
        if (_showLineNumbers) {
            NSString* lineNumber = [NSString stringWithFormat:@"%lu", (unsigned long)(index + 1)];
            NSSize numberSize = [lineNumber sizeWithAttributes:lineNumberAttributes];
            [lineNumber drawAtPoint:NSMakePoint(76.0 - numberSize.width, y)
                     withAttributes:lineNumberAttributes];
        }
        NSRange selection = [self selectionRange];
        NSUInteger lineEnd = currentLineStart + line.length;
        NSUInteger selectionStart = selection.location;
        NSUInteger selectionEnd = NSMaxRange(selection);
        NSUInteger segmentStart = MAX(selectionStart, currentLineStart);
        NSUInteger segmentEnd = MIN(selectionEnd, lineEnd);
        BOOL selectsNewline =
            index + 1 < lines.count && selectionStart <= lineEnd && selectionEnd > lineEnd;
        if (segmentEnd > segmentStart || selectsNewline) {
            NSString* beforeSelection =
                [line substringToIndex:MIN(segmentStart - currentLineStart, line.length)];
            NSString* selectedText =
                [line substringWithRange:NSMakeRange(segmentStart - currentLineStart,
                                                     segmentEnd - segmentStart)];
            CGFloat selectionX = kTextOriginX - _horizontalScroll +
                                 [beforeSelection sizeWithAttributes:textAttributes].width;
            CGFloat selectionWidth = [selectedText sizeWithAttributes:textAttributes].width;
            if (selectsNewline) {
                selectionWidth += 7.8;
            }
            [editorColor(77, 141, 255, 0.34) setFill];
            NSRectFill(NSMakeRect(floor(selectionX), y, MAX(1.5, selectionWidth), _lineHeight));
        }
        [line drawAtPoint:NSMakePoint(kTextOriginX - _horizontalScroll, y)
            withAttributes:textAttributes];
    }

    NSString* beforeCaret = [_text substringToIndex:_caretIndex];
    NSArray<NSString*>* caretLines = [beforeCaret componentsSeparatedByString:@"\n"];
    NSString* caretLine = caretLines.lastObject ?: @"";
    CGFloat caretX =
        kTextOriginX - _horizontalScroll + [caretLine sizeWithAttributes:textAttributes].width;
    CGFloat caretY = kFirstLineY + (caretLines.count - 1) * _lineHeight - _verticalScroll;
    [editorColor(111, 166, 255) setFill];
    NSRectFill(NSMakeRect(floor(caretX), caretY + 1.0, 1.5, 16.0));
    [NSGraphicsContext restoreGraphicsState];

    CGFloat maximumVertical = [self maximumVerticalScroll];
    if (_showScrollIndicators && maximumVertical > 0.0) {
        NSRect track = NSMakeRect(NSWidth(self.bounds) - 7.0, 74.0, 3.0,
                                  MAX(20.0, NSHeight(self.bounds) - 82.0));
        CGFloat contentHeight = lines.count * _lineHeight;
        CGFloat thumbHeight = MAX(28.0, NSHeight(track) * NSHeight(track) / contentHeight);
        CGFloat thumbY =
            NSMinY(track) + (NSHeight(track) - thumbHeight) * (_verticalScroll / maximumVertical);
        [editorColor(139, 155, 177, 0.38) setFill];
        [[NSBezierPath
            bezierPathWithRoundedRect:NSMakeRect(NSMinX(track), thumbY, NSWidth(track), thumbHeight)
                              xRadius:1.5
                              yRadius:1.5] fill];
    }

    CGFloat maximumHorizontal = [self maximumHorizontalScroll];
    if (_showScrollIndicators && maximumHorizontal > 0.0) {
        NSRect track = NSMakeRect(kTextOriginX, NSHeight(self.bounds) - 6.0,
                                  MAX(20.0, NSWidth(self.bounds) - 104.0), 3.0);
        CGFloat thumbWidth =
            MAX(32.0, NSWidth(track) * NSWidth(track) / (NSWidth(track) + maximumHorizontal));
        CGFloat thumbX =
            NSMinX(track) + (NSWidth(track) - thumbWidth) * (_horizontalScroll / maximumHorizontal);
        [editorColor(139, 155, 177, 0.38) setFill];
        [[NSBezierPath
            bezierPathWithRoundedRect:NSMakeRect(thumbX, NSMinY(track), thumbWidth, NSHeight(track))
                              xRadius:1.5
                              yRadius:1.5] fill];
    }

    [self drawContextMenu];
}

- (void)mouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (_contextMenuVisible) {
        NSInteger menuIndex = [self contextMenuIndexAtPoint:point];
        [self hideContextMenu];
        if (menuIndex >= 0) {
            [self performContextMenuItem:menuIndex];
            return;
        }
    }
    if (NSPointInRect(point, [self closeRect])) {
        if (_settingsVisible) {
            _settingsVisible = NO;
            [_activityBar deactivateSection];
            self.needsDisplay = YES;
            return;
        }
        [self.commandHandler closeActiveTab];
        return;
    }
    [self.window makeFirstResponder:self];
    if (_settingsVisible) {
        [self applySettingsControl:[self settingsControlAtPoint:point]];
        return;
    }
    if (point.y < 68.0) {
        return;
    }

    NSUInteger index = [self textIndexForPoint:point];
    if ((event.modifierFlags & NSEventModifierFlagShift) == 0) {
        _selectionAnchor = index;
    }
    _caretIndex = index;
    _draggingSelection = YES;
    [self ensureCaretVisible];
    self.needsDisplay = YES;
}

- (void)rightMouseDown:(NSEvent*)event {
    if (_settingsVisible) {
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (point.y < 68.0) {
        [self hideContextMenu];
        return;
    }

    [self.window makeFirstResponder:self];
    NSUInteger index = [self textIndexForPoint:point];
    NSRange selection = [self selectionRange];
    BOOL clickedSelection =
        selection.length > 0 && index >= selection.location && index <= NSMaxRange(selection);
    if (!clickedSelection) {
        _caretIndex = index;
        _selectionAnchor = index;
    }
    [self showContextMenuAtPoint:point];
}

- (void)mouseDragged:(NSEvent*)event {
    if (!_draggingSelection) {
        return;
    }

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (point.y < kFirstLineY) {
        _verticalScroll -= _lineHeight;
    } else if (point.y > NSHeight(self.bounds) - 8.0) {
        _verticalScroll += _lineHeight;
    }
    if (point.x < kTextOriginX) {
        _horizontalScroll -= 12.0;
    } else if (point.x > NSWidth(self.bounds) - 8.0) {
        _horizontalScroll += 12.0;
    }
    [self clampScroll];
    _caretIndex = [self textIndexForPoint:point];
    [self ensureCaretVisible];
    self.needsDisplay = YES;
}

- (void)mouseUp:(NSEvent*)event {
    (void)event;
    _draggingSelection = NO;
}

- (void)resetCursorRects {
    [super resetCursorRects];
    if (_settingsVisible) {
        [self addCursorRect:NSMakeRect(KineticActivityBar.railWidth, 68.0,
                                       NSWidth(self.bounds) - KineticActivityBar.railWidth,
                                       MAX(0.0, NSHeight(self.bounds) - 68.0))
                     cursor:NSCursor.arrowCursor];
        return;
    }
    NSRect editorRect = NSMakeRect(KineticActivityBar.railWidth, 68.0,
                                   NSWidth(self.bounds) - KineticActivityBar.railWidth,
                                   MAX(0.0, NSHeight(self.bounds) - 68.0));
    [self addCursorRect:editorRect cursor:NSCursor.IBeamCursor];
    if (_contextMenuVisible) {
        [self addCursorRect:_contextMenuFrame cursor:NSCursor.arrowCursor];
    }
}

- (void)activityBarDidRequestOpenFile:(KineticActivityBar*)activityBar {
    (void)activityBar;
    [self.commandHandler openFile];
}

- (void)activityBarDidRequestOpenFolder:(KineticActivityBar*)activityBar {
    (void)activityBar;
    [self.commandHandler openFolder];
}

- (void)activityBar:(KineticActivityBar*)activityBar didRequestOpenUrl:(NSURL*)url {
    (void)activityBar;
    [self.commandHandler openFileAtUrl:url];
}

- (void)activityBar:(KineticActivityBar*)activityBar
    didActivateSection:(KineticActivitySection)section {
    (void)activityBar;
    _settingsVisible = section == KineticActivitySectionSettings;
    [self.window invalidateCursorRectsForView:self];
    self.needsDisplay = YES;
}

- (void)updateTrackingAreas {
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                     NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
               owner:self
            userInfo:nil];
    [self addTrackingArea:_trackingArea];
    [super updateTrackingAreas];
}

- (void)mouseMoved:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger settingsControl = _settingsVisible ? [self settingsControlAtPoint:point] : -1;
    if (settingsControl != _settingsHoveredControl) {
        _settingsHoveredControl = settingsControl;
        self.needsDisplay = YES;
    }
    NSInteger menuIndex = [self contextMenuIndexAtPoint:point];
    if (menuIndex != _contextMenuHoveredIndex) {
        _contextMenuHoveredIndex = menuIndex;
        self.needsDisplay = YES;
    }
    BOOL hovered = NSPointInRect(point, [self closeRect]);
    if (hovered != _closeHovered) {
        _closeHovered = hovered;
        self.needsDisplay = YES;
    }
}

- (void)mouseExited:(NSEvent*)event {
    (void)event;
    _closeHovered = NO;
    _settingsHoveredControl = -1;
    self.needsDisplay = YES;
}

- (void)scrollWheel:(NSEvent*)event {
    if (_settingsVisible) {
        return;
    }
    [self hideContextMenu];
    BOOL horizontal = fabs(event.scrollingDeltaX) > fabs(event.scrollingDeltaY) ||
                      (event.modifierFlags & NSEventModifierFlagShift) != 0;
    if (horizontal) {
        CGFloat delta =
            fabs(event.scrollingDeltaX) > 0.0 ? event.scrollingDeltaX : event.scrollingDeltaY;
        _horizontalScroll += _naturalScrolling ? -delta : delta;
    } else {
        _verticalScroll += _naturalScrolling ? -event.scrollingDeltaY : event.scrollingDeltaY;
    }
    [self clampScroll];
    self.needsDisplay = YES;
}

- (void)keyDown:(NSEvent*)event {
    if (_settingsVisible) {
        if (event.keyCode == 53) {
            _settingsVisible = NO;
            [_activityBar deactivateSection];
            [self.window invalidateCursorRectsForView:self];
            self.needsDisplay = YES;
        }
        return;
    }
    [self hideContextMenu];
    BOOL usesCommand = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    BOOL usesOption = (event.modifierFlags & NSEventModifierFlagOption) != 0;
    BOOL extendsSelection = (event.modifierFlags & NSEventModifierFlagShift) != 0;
    NSString* shortcut = event.charactersIgnoringModifiers.lowercaseString;

    if (usesCommand && [shortcut isEqualToString:@"c"]) {
        [self copySelection];
        return;
    }
    if (usesCommand && [shortcut isEqualToString:@"x"]) {
        [self cutSelection];
        [self ensureCaretVisible];
        self.needsDisplay = YES;
        return;
    }
    if (usesCommand && [shortcut isEqualToString:@"v"]) {
        [self pasteText];
        [self ensureCaretVisible];
        self.needsDisplay = YES;
        return;
    }
    if (usesCommand && [shortcut isEqualToString:@"a"]) {
        [self selectAllText];
        return;
    }
    if (usesCommand && [shortcut isEqualToString:@"z"]) {
        if (extendsSelection) {
            [self redoEdit];
        } else {
            [self undoEdit];
        }
        return;
    }
    if (usesCommand && [shortcut isEqualToString:@"y"]) {
        [self redoEdit];
        return;
    }

    NSRange initialSelection = [self selectionRange];

    if (event.keyCode == 51) {
        if (initialSelection.length > 0) {
            [self recordUndoState];
            [self deleteSelection];
        } else if (_caretIndex > 0) {
            NSUInteger deletionStart = 0;
            if (usesCommand) {
                deletionStart = [self lineStartIndexFromIndex:_caretIndex];
                if (deletionStart == _caretIndex) {
                    --deletionStart;
                }
            } else if (usesOption) {
                deletionStart = [self previousWordIndexFromIndex:_caretIndex];
            } else {
                deletionStart =
                    [_text rangeOfComposedCharacterSequenceAtIndex:_caretIndex - 1].location;
            }
            [self recordUndoState];
            [_text deleteCharactersInRange:NSMakeRange(deletionStart, _caretIndex - deletionStart)];
            _caretIndex = deletionStart;
            _selectionAnchor = _caretIndex;
            [self updateDirtyState];
        }
    } else if (event.keyCode == 117) {
        if (initialSelection.length > 0) {
            [self recordUndoState];
            [self deleteSelection];
        } else if (_caretIndex < _text.length) {
            NSUInteger deletionEnd = 0;
            if (usesCommand) {
                deletionEnd = [self lineEndIndexFromIndex:_caretIndex];
                if (deletionEnd == _caretIndex) {
                    ++deletionEnd;
                }
            } else if (usesOption) {
                deletionEnd = [self nextWordIndexFromIndex:_caretIndex];
            } else {
                deletionEnd =
                    NSMaxRange([_text rangeOfComposedCharacterSequenceAtIndex:_caretIndex]);
            }
            [self recordUndoState];
            [_text deleteCharactersInRange:NSMakeRange(_caretIndex, deletionEnd - _caretIndex)];
            _selectionAnchor = _caretIndex;
            [self updateDirtyState];
        }
    } else if (event.keyCode == 36 || event.keyCode == 76) {
        [self replaceSelectionWithString:@"\n"];
    } else if (event.keyCode == 48) {
        [self replaceSelectionWithString:@"    "];
    } else if (event.keyCode == 123) {
        if (!extendsSelection && initialSelection.length > 0) {
            _caretIndex = initialSelection.location;
        } else if (usesCommand) {
            _caretIndex = [self lineStartIndexFromIndex:_caretIndex];
        } else if (usesOption) {
            _caretIndex = [self previousWordIndexFromIndex:_caretIndex];
        } else if (_caretIndex > 0) {
            _caretIndex = [_text rangeOfComposedCharacterSequenceAtIndex:_caretIndex - 1].location;
        }
        if (!extendsSelection) {
            _selectionAnchor = _caretIndex;
        }
    } else if (event.keyCode == 124) {
        if (!extendsSelection && initialSelection.length > 0) {
            _caretIndex = NSMaxRange(initialSelection);
        } else if (usesCommand) {
            _caretIndex = [self lineEndIndexFromIndex:_caretIndex];
        } else if (usesOption) {
            _caretIndex = [self nextWordIndexFromIndex:_caretIndex];
        } else if (_caretIndex < _text.length) {
            _caretIndex = NSMaxRange([_text rangeOfComposedCharacterSequenceAtIndex:_caretIndex]);
        }
        if (!extendsSelection) {
            _selectionAnchor = _caretIndex;
        }
    } else if (event.keyCode == 126) {
        if (usesCommand) {
            _caretIndex = 0;
        } else {
            [self moveCaretVertically:-1];
        }
        if (!extendsSelection) {
            _selectionAnchor = _caretIndex;
        }
    } else if (event.keyCode == 125) {
        if (usesCommand) {
            _caretIndex = _text.length;
        } else {
            [self moveCaretVertically:1];
        }
        if (!extendsSelection) {
            _selectionAnchor = _caretIndex;
        }
    } else if (event.keyCode == 116) {
        NSInteger pageLines = MAX(1, floor((NSHeight(self.bounds) - kFirstLineY) / _lineHeight));
        [self moveCaretVertically:-pageLines];
        if (!extendsSelection) {
            _selectionAnchor = _caretIndex;
        }
    } else if (event.keyCode == 121) {
        NSInteger pageLines = MAX(1, floor((NSHeight(self.bounds) - kFirstLineY) / _lineHeight));
        [self moveCaretVertically:pageLines];
        if (!extendsSelection) {
            _selectionAnchor = _caretIndex;
        }
    } else {
        if (usesCommand) {
            [super keyDown:event];
            return;
        }
        NSString* characters = event.characters;
        if (characters.length == 0 || [characters characterAtIndex:0] < 0x20) {
            [super keyDown:event];
            return;
        }
        [self replaceSelectionWithString:characters];
    }

    [self ensureCaretVisible];
    self.needsDisplay = YES;
}

@end
