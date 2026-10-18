#import "searchPopover.h"
#import "contextMenu.h"
#import "theme.h"

namespace {

constexpr CGFloat kFileResultsY = 213.0;
constexpr CGFloat kProjectResultsY = 151.0;
constexpr CGFloat kResultHeight = 44.0;

NSColor* searchColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha = 1.0) {
    return kineticThemeColor(red, green, blue, alpha);
}

} // namespace

@interface KineticSearchPopover () {
    NSMutableString* _query;
    NSMutableString* _replacement;
    NSArray<NSDictionary*>* _results;
    NSUInteger _caretIndex;
    NSInteger _selectedResult;
    NSInteger _hoveredResult;
    CGFloat _scrollOffset;
    BOOL _selectAll;
    NSUInteger _replacementCaret;
    BOOL _replacementSelectAll;
    BOOL _editingReplacement;
    BOOL _loading;
    BOOL _truncated;
    BOOL _matchCase;
    KineticSearchScope _scope;
    NSTrackingArea* _trackingArea;
}
@end

@implementation KineticSearchPopover

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _query = [NSMutableString string];
        _replacement = [NSMutableString string];
        _results = @[];
        _selectedResult = -1;
        _hoveredResult = -1;
        _scope = KineticSearchScopeFile;
        self.wantsLayer = YES;
        self.layer.shadowColor = NSColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.28;
        self.layer.shadowRadius = 16.0;
        self.layer.shadowOffset = CGSizeMake(0.0, -5.0);
    }
    return self;
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

- (NSString*)query {
    return [_query copy];
}

- (NSString*)replacement {
    return [_replacement copy];
}

- (KineticSearchScope)scope {
    return _scope;
}

- (BOOL)matchCase {
    return _matchCase;
}

- (NSArray<NSDictionary*>*)results {
    return _results;
}

- (NSDictionary*)searchState {
    return @{
        @"query" : [_query copy],
        @"replacement" : [_replacement copy],
        @"scope" : @(_scope),
        @"matchCase" : @(_matchCase),
        @"results" : _results,
        @"loading" : @(_loading),
        @"truncated" : @(_truncated),
    };
}

- (void)applySearchState:(NSDictionary*)state {
    NSString* query = state[@"query"];
    [_query setString:[query isKindOfClass:NSString.class] ? query : @""];
    NSString* replacement = state[@"replacement"];
    [_replacement setString:[replacement isKindOfClass:NSString.class] ? replacement : @""];
    _replacementCaret = _replacement.length;
    _caretIndex = _query.length;
    _scope = [state[@"scope"] integerValue] == KineticSearchScopeProject ? KineticSearchScopeProject
                                                                         : KineticSearchScopeFile;
    _matchCase = [state[@"matchCase"] boolValue];
    NSArray<NSDictionary*>* results = state[@"results"];
    _results = [results isKindOfClass:NSArray.class] ? [results copy] : @[];
    _loading = [state[@"loading"] boolValue];
    _truncated = [state[@"truncated"] boolValue];
    _selectedResult = _results.count > 0 ? 0 : -1;
    _scrollOffset = 0.0;
    _selectAll = NO;
    _replacementSelectAll = NO;
    _editingReplacement = NO;
    self.needsDisplay = YES;
}

- (void)selectScope:(KineticSearchScope)scope {
    if (_scope == scope) {
        return;
    }
    _scope = scope;
    _selectedResult = -1;
    _scrollOffset = 0.0;
    [self.delegate searchPopoverDidChange:self];
    self.needsDisplay = YES;
}

- (void)applyResults:(NSArray<NSDictionary*>*)results
             loading:(BOOL)loading
           truncated:(BOOL)truncated {
    _results = [results copy];
    _loading = loading;
    _truncated = truncated;
    _selectedResult = _results.count > 0 ? 0 : -1;
    _scrollOffset = 0.0;
    self.needsDisplay = YES;
}

- (void)focusQuery {
    _editingReplacement = NO;
    [self.window makeFirstResponder:self];
    self.needsDisplay = YES;
}

- (CGFloat)preferredHeight {
    CGFloat extraHeight = _scope == KineticSearchScopeFile ? 62.0 : 0.0;
    if (_query.length == 0 || _results.count == 0) {
        return 165.0 + extraHeight;
    }
    return 159.0 + extraHeight + MIN((NSUInteger)5, _results.count) * kResultHeight;
}

- (CGFloat)resultsY {
    return _scope == KineticSearchScopeFile ? kFileResultsY : kProjectResultsY;
}

- (NSRect)closeRect {
    return NSMakeRect(NSWidth(self.bounds) - 29.0, 10.0, 20.0, 20.0);
}

- (NSRect)fileScopeRect {
    return NSMakeRect(13.0, 42.0, 104.0, 27.0);
}

- (NSRect)projectScopeRect {
    return NSMakeRect(123.0, 42.0, 88.0, 27.0);
}

- (NSRect)queryRect {
    return NSMakeRect(13.0, 80.0, NSWidth(self.bounds) - 60.0, 31.0);
}

- (NSRect)caseRect {
    return NSMakeRect(NSWidth(self.bounds) - 42.0, 80.0, 29.0, 31.0);
}

- (NSRect)replacementRect {
    return NSMakeRect(13.0, 119.0, NSWidth(self.bounds) - 26.0, 31.0);
}

- (NSRect)replaceRect {
    return NSMakeRect(NSWidth(self.bounds) - 154.0, 157.0, 68.0, 27.0);
}

- (NSRect)replaceAllRect {
    return NSMakeRect(NSWidth(self.bounds) - 81.0, 157.0, 68.0, 27.0);
}

- (NSRect)resultRectAtIndex:(NSUInteger)index {
    return NSMakeRect(7.0, [self resultsY] + index * kResultHeight - _scrollOffset,
                      NSWidth(self.bounds) - 14.0, kResultHeight);
}

- (CGFloat)maximumScroll {
    return MAX(0.0, _results.count * kResultHeight -
                        MAX(1.0, NSHeight(self.bounds) - [self resultsY] - 8.0));
}

- (void)drawScope:(NSString*)title inRect:(NSRect)rect selected:(BOOL)selected {
    if (selected) {
        [searchColor(77, 141, 255, 0.20) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:5.0 yRadius:5.0] fill];
    }
    NSDictionary* attributes = @{
        NSFontAttributeName :
            [NSFont systemFontOfSize:11.0
                              weight:selected ? NSFontWeightSemibold : NSFontWeightMedium],
        NSForegroundColorAttributeName : selected ? searchColor(130, 178, 255)
                                                  : searchColor(158, 173, 193),
    };
    [title drawAtPoint:NSMakePoint(NSMinX(rect) + 10.0, NSMinY(rect) + 6.0)
        withAttributes:attributes];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect bounds = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath* panel = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:9.0 yRadius:9.0];
    [searchColor(38, 47, 61, 0.99) setFill];
    [panel fill];
    [searchColor(93, 109, 130, 0.52) setStroke];
    [panel stroke];

    NSDictionary* heading = @{
        NSFontAttributeName : [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName : searchColor(164, 179, 198),
    };
    [@"SEARCH" drawAtPoint:NSMakePoint(15.0, 14.0) withAttributes:heading];
    NSRect closeRect = [self closeRect];
    NSBezierPath* close = [NSBezierPath bezierPath];
    close.lineWidth = 1.25;
    [close moveToPoint:NSMakePoint(NSMinX(closeRect) + 6.0, NSMinY(closeRect) + 6.0)];
    [close lineToPoint:NSMakePoint(NSMaxX(closeRect) - 6.0, NSMaxY(closeRect) - 6.0)];
    [close moveToPoint:NSMakePoint(NSMaxX(closeRect) - 6.0, NSMinY(closeRect) + 6.0)];
    [close lineToPoint:NSMakePoint(NSMinX(closeRect) + 6.0, NSMaxY(closeRect) - 6.0)];
    [searchColor(160, 175, 195) setStroke];
    [close stroke];

    [self drawScope:@"This File"
             inRect:[self fileScopeRect]
           selected:_scope == KineticSearchScopeFile];
    [self drawScope:@"Project"
             inRect:[self projectScopeRect]
           selected:_scope == KineticSearchScopeProject];

    NSRect queryRect = [self queryRect];
    [searchColor(29, 38, 51) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:queryRect xRadius:5.0 yRadius:5.0] fill];
    BOOL queryFocused = self.window.firstResponder == self && !_editingReplacement;
    [searchColor(queryFocused ? 77 : 75, queryFocused ? 141 : 89, queryFocused ? 255 : 109, 0.72)
        setStroke];
    [[NSBezierPath bezierPathWithRoundedRect:queryRect xRadius:5.0 yRadius:5.0] stroke];
    NSDictionary* queryAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12.5],
        NSForegroundColorAttributeName : searchColor(229, 236, 246),
    };
    NSString* visibleQuery = [_query copy];
    NSUInteger visibleStart = 0;
    CGFloat availableWidth = NSWidth(queryRect) - 18.0;
    while (visibleQuery.length > 0 &&
           [visibleQuery sizeWithAttributes:queryAttributes].width > availableWidth) {
        NSRange first = [visibleQuery rangeOfComposedCharacterSequenceAtIndex:0];
        visibleStart += NSMaxRange(first);
        visibleQuery = [visibleQuery substringFromIndex:NSMaxRange(first)];
    }
    NSPoint queryPoint = NSMakePoint(NSMinX(queryRect) + 9.0, NSMinY(queryRect) + 7.0);
    if (_query.length == 0) {
        [@"Find text or files…" drawAtPoint:queryPoint
                             withAttributes:@{
                                 NSFontAttributeName : [NSFont systemFontOfSize:12.5],
                                 NSForegroundColorAttributeName : searchColor(126, 142, 163),
                             }];
    } else {
        if (_selectAll) {
            [searchColor(77, 141, 255, 0.35) setFill];
            NSRectFill(NSMakeRect(queryPoint.x - 1.0, queryPoint.y - 1.0,
                                  [visibleQuery sizeWithAttributes:queryAttributes].width + 2.0,
                                  18.0));
        }
        [visibleQuery drawAtPoint:queryPoint withAttributes:queryAttributes];
    }
    if (self.window.firstResponder == self && !_selectAll && !_editingReplacement) {
        NSUInteger caretInVisible =
            MIN(visibleQuery.length, _caretIndex > visibleStart ? _caretIndex - visibleStart : 0);
        CGFloat caretX = queryPoint.x + [[visibleQuery substringToIndex:caretInVisible]
                                            sizeWithAttributes:queryAttributes]
                                            .width;
        [searchColor(111, 166, 255) setFill];
        NSRectFill(NSMakeRect(caretX, queryPoint.y, 1.5, 17.0));
    }

    NSRect caseRect = [self caseRect];
    if (_matchCase) {
        [searchColor(77, 141, 255, 0.20) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:caseRect xRadius:5.0 yRadius:5.0] fill];
    }
    [@"Aa" drawAtPoint:NSMakePoint(NSMinX(caseRect) + 6.0, NSMinY(caseRect) + 8.0)
        withAttributes:@{
            NSFontAttributeName : [NSFont systemFontOfSize:11.5 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName : _matchCase ? searchColor(130, 178, 255)
                                                        : searchColor(155, 170, 189),
        }];

    if (_scope == KineticSearchScopeFile) {
        NSRect replacementRect = [self replacementRect];
        [searchColor(29, 38, 51) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:replacementRect xRadius:5.0 yRadius:5.0] fill];
        [searchColor(_editingReplacement && self.window.firstResponder == self ? 77 : 75,
                     _editingReplacement && self.window.firstResponder == self ? 141 : 89,
                     _editingReplacement && self.window.firstResponder == self ? 255 : 109, 0.72)
            setStroke];
        [[NSBezierPath bezierPathWithRoundedRect:replacementRect xRadius:5.0 yRadius:5.0] stroke];
        NSString* replacementLabel = _replacement.length > 0 ? _replacement : @"Replace with…";
        if (_replacementSelectAll && _editingReplacement && _replacement.length > 0) {
            [searchColor(77, 141, 255, 0.35) setFill];
            NSRectFill(NSInsetRect(replacementRect, 9.0, 6.0));
        }
        [replacementLabel drawInRect:NSInsetRect(replacementRect, 9.0, 7.0)
                      withAttributes:@{
                          NSFontAttributeName : [NSFont systemFontOfSize:12.5],
                          NSForegroundColorAttributeName : _replacement.length > 0
                              ? searchColor(229, 236, 246)
                              : searchColor(126, 142, 163),
                      }];
        if (_editingReplacement && self.window.firstResponder == self && !_replacementSelectAll) {
            CGFloat caretX =
                NSMinX(replacementRect) + 9.0 +
                [[_replacement substringToIndex:MIN(_replacementCaret, _replacement.length)]
                    sizeWithAttributes:queryAttributes]
                    .width;
            [searchColor(111, 166, 255) setFill];
            NSRectFill(NSMakeRect(MIN(caretX, NSMaxX(replacementRect) - 10.0),
                                  NSMinY(replacementRect) + 7.0, 1.5, 17.0));
        }
        BOOL canReplace =
            _scope == KineticSearchScopeFile && _query.length > 0 && _results.count > 0;
        for (NSString* title in @[ @"Replace", @"All" ]) {
            NSRect button =
                [title isEqualToString:@"All"] ? [self replaceAllRect] : [self replaceRect];
            [searchColor(77, 141, 255, canReplace ? 0.21 : 0.08) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:button xRadius:5.0 yRadius:5.0] fill];
            [title drawInRect:NSInsetRect(button, 9.0, 5.0)
                withAttributes:@{
                    NSFontAttributeName : [NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium],
                    NSForegroundColorAttributeName : canReplace ? searchColor(180, 209, 255)
                                                                : searchColor(115, 130, 150),
                }];
        }
    }
    NSString* status = _scope == KineticSearchScopeFile ? @"Type to find in this file."
                                                        : @"Type to search the project.";
    if (_scope == KineticSearchScopeProject && !_projectAvailable) {
        status = @"Open a folder to search the project.";
    } else if (_loading) {
        status = @"Searching…";
    } else if (_query.length > 0) {
        status = [NSString stringWithFormat:@"%lu%@ %@", (unsigned long)_results.count,
                                            _truncated ? @"+" : @"",
                                            _results.count == 1 ? @"match" : @"matches"];
    }
    [status drawAtPoint:NSMakePoint(16.0, [self resultsY] - 23.0)
         withAttributes:@{
             NSFontAttributeName : [NSFont systemFontOfSize:11.0],
             NSForegroundColorAttributeName : searchColor(142, 158, 180),
         }];

    NSRect clip = NSMakeRect(2.0, [self resultsY], NSWidth(self.bounds) - 4.0,
                             MAX(0.0, NSHeight(self.bounds) - [self resultsY] - 3.0));
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:clip] addClip];
    NSMutableParagraphStyle* truncation = [[NSMutableParagraphStyle alloc] init];
    truncation.lineBreakMode = NSLineBreakByTruncatingTail;
    for (NSUInteger index = 0; index < _results.count; ++index) {
        NSRect row = [self resultRectAtIndex:index];
        if (NSMinY(row) >= NSMaxY(clip)) {
            break;
        }
        if (NSMaxY(row) <= NSMinY(clip)) {
            continue;
        }
        if (_selectedResult == (NSInteger)index || _hoveredResult == (NSInteger)index) {
            [searchColor(77, 141, 255, _selectedResult == (NSInteger)index ? 0.16 : 0.10) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:row xRadius:5.0 yRadius:5.0] fill];
        }
        NSDictionary* result = _results[index];
        NSUInteger line = [result[@"line"] unsignedIntegerValue];
        NSUInteger column = [result[@"column"] unsignedIntegerValue];
        NSString* title =
            _scope == KineticSearchScopeProject
                ? [NSString stringWithFormat:@"%@: %lu", result[@"relativePath"] ?: @"File",
                                             (unsigned long)line]
                : [NSString stringWithFormat:@"Line %lu · Col %lu", (unsigned long)line,
                                             (unsigned long)column];
        [title drawInRect:NSMakeRect(NSMinX(row) + 10.0, NSMinY(row) + 5.0, NSWidth(row) - 20.0,
                                     16.0)
            withAttributes:@{
                NSFontAttributeName : [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium],
                NSForegroundColorAttributeName : searchColor(216, 229, 246),
                NSParagraphStyleAttributeName : truncation,
            }];
        [result[@"preview"] drawInRect:NSMakeRect(NSMinX(row) + 10.0, NSMinY(row) + 23.0,
                                                  NSWidth(row) - 20.0, 16.0)
                        withAttributes:@{
                            NSFontAttributeName :
                                [NSFont monospacedSystemFontOfSize:10.5 weight:NSFontWeightRegular],
                            NSForegroundColorAttributeName : searchColor(151, 168, 190),
                            NSParagraphStyleAttributeName : truncation,
                        }];
    }
    [NSGraphicsContext restoreGraphicsState];
}

- (void)updateTrackingAreas {
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                     NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
               owner:self
            userInfo:nil];
    [self addTrackingArea:_trackingArea];
    [super updateTrackingAreas];
}

- (void)mouseMoved:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger hovered = -1;
    for (NSUInteger index = 0; point.y >= [self resultsY] && index < _results.count; ++index) {
        if (NSPointInRect(point, [self resultRectAtIndex:index])) {
            hovered = (NSInteger)index;
            break;
        }
    }
    if (_hoveredResult != hovered) {
        _hoveredResult = hovered;
        self.needsDisplay = YES;
    }
}

- (void)mouseExited:(NSEvent*)event {
    (void)event;
    _hoveredResult = -1;
    self.needsDisplay = YES;
}

- (void)mouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(point, [self closeRect])) {
        [self.delegate searchPopoverDidRequestClose:self];
    } else if (NSPointInRect(point, [self fileScopeRect])) {
        [self selectScope:KineticSearchScopeFile];
        [self focusQuery];
    } else if (NSPointInRect(point, [self projectScopeRect])) {
        [self selectScope:KineticSearchScopeProject];
        [self focusQuery];
    } else if (NSPointInRect(point, [self caseRect])) {
        _matchCase = !_matchCase;
        [self.delegate searchPopoverDidChange:self];
        [self focusQuery];
    } else if (_scope == KineticSearchScopeFile && NSPointInRect(point, [self replaceRect]) &&
               _results.count > 0) {
        NSUInteger index = _selectedResult >= 0 ? (NSUInteger)_selectedResult : 0;
        [self.delegate searchPopover:self didRequestReplaceResult:_results[index]];
    } else if (_scope == KineticSearchScopeFile && NSPointInRect(point, [self replaceAllRect]) &&
               _results.count > 0) {
        [self.delegate searchPopoverDidRequestReplaceAll:self];
    } else if (_scope == KineticSearchScopeFile && NSPointInRect(point, [self replacementRect])) {
        _editingReplacement = YES;
        _replacementSelectAll = NO;
        _replacementCaret = _replacement.length;
        [self.window makeFirstResponder:self];
        self.needsDisplay = YES;
    } else if (NSPointInRect(point, [self queryRect])) {
        _editingReplacement = NO;
        _selectAll = NO;
        _caretIndex = _query.length;
        [self focusQuery];
    } else {
        for (NSUInteger index = 0; point.y >= [self resultsY] && index < _results.count; ++index) {
            if (NSPointInRect(point, [self resultRectAtIndex:index])) {
                [self.delegate searchPopover:self didSelectResult:_results[index]];
                return;
            }
        }
    }
    self.needsDisplay = YES;
}

- (void)rightMouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    BOOL replacementField =
        _scope == KineticSearchScopeFile && NSPointInRect(point, [self replacementRect]);
    if (!replacementField && !NSPointInRect(point, [self queryRect])) {
        return;
    }
    _editingReplacement = replacementField;
    NSMutableString* field = replacementField ? _replacement : _query;
    BOOL* selected = replacementField ? &_replacementSelectAll : &_selectAll;
    NSString* pasted = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
    [KineticContextMenu
        showInView:self
           atPoint:point
             items:@[
                 @{
                     @"title" : replacementField ? @"Copy Replacement" : @"Copy Query",
                     @"enabled" : @(field.length > 0)
                 },
                 @{@"title" : @"Paste", @"enabled" : @(pasted.length > 0)},
                 @{@"title" : @"Select All", @"enabled" : @(field.length > 0)},
                 @{@"title" : @"Clear", @"enabled" : @(field.length > 0)}
             ]
           handler:^(NSUInteger index) {
             if (index == 0) {
                 [NSPasteboard.generalPasteboard clearContents];
                 [NSPasteboard.generalPasteboard setString:field forType:NSPasteboardTypeString];
             } else if (index == 1) {
                 NSString* oneLine = [[pasted
                     componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]
                     componentsJoinedByString:@" "];
                 [self replaceSelectionWithText:oneLine];
             } else if (index == 2) {
                 *selected = YES;
                 self.needsDisplay = YES;
             } else {
                 *selected = YES;
                 [self replaceSelectionWithText:@""];
             }
           }];
}

- (void)scrollWheel:(NSEvent*)event {
    _scrollOffset = MIN([self maximumScroll], MAX(0.0, _scrollOffset - event.scrollingDeltaY));
    self.needsDisplay = YES;
}

- (void)replaceSelectionWithText:(NSString*)text {
    NSMutableString* field = _editingReplacement ? _replacement : _query;
    NSUInteger* caret = _editingReplacement ? &_replacementCaret : &_caretIndex;
    BOOL* selected = _editingReplacement ? &_replacementSelectAll : &_selectAll;
    if (*selected) {
        [field setString:@""];
        *caret = 0;
        *selected = NO;
    }
    if (field.length + text.length > 200) {
        return;
    }
    [field insertString:text atIndex:*caret];
    *caret += text.length;
    if (!_editingReplacement) {
        [self.delegate searchPopoverDidChange:self];
    }
    self.needsDisplay = YES;
}

- (void)keyDown:(NSEvent*)event {
    BOOL command = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    NSString* key = event.charactersIgnoringModifiers.lowercaseString;
    NSMutableString* field = _editingReplacement ? _replacement : _query;
    NSUInteger* caret = _editingReplacement ? &_replacementCaret : &_caretIndex;
    BOOL* selected = _editingReplacement ? &_replacementSelectAll : &_selectAll;
    if (event.keyCode == 53) {
        [self.delegate searchPopoverDidRequestClose:self];
        return;
    }
    if (command && [key isEqualToString:@"a"]) {
        *selected = YES;
        self.needsDisplay = YES;
        return;
    }
    if (command && ([key isEqualToString:@"c"] || [key isEqualToString:@"x"])) {
        if (*selected) {
            [NSPasteboard.generalPasteboard clearContents];
            [NSPasteboard.generalPasteboard setString:field forType:NSPasteboardTypeString];
            if ([key isEqualToString:@"x"]) {
                [self replaceSelectionWithText:@""];
            }
        }
        return;
    }
    if (command && [key isEqualToString:@"v"]) {
        NSString* pasted = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
        NSString* oneLine = [[(
            pasted ?: @"") componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]
            componentsJoinedByString:@" "];
        [self replaceSelectionWithText:oneLine];
        return;
    }
    if (event.keyCode == 51 || event.keyCode == 117) {
        if (*selected) {
            [self replaceSelectionWithText:@""];
        } else if (event.keyCode == 51 && *caret > 0) {
            NSRange previous = [field rangeOfComposedCharacterSequenceAtIndex:*caret - 1];
            [field deleteCharactersInRange:previous];
            *caret = previous.location;
            if (!_editingReplacement)
                [self.delegate searchPopoverDidChange:self];
        } else if (event.keyCode == 117 && *caret < field.length) {
            NSRange next = [field rangeOfComposedCharacterSequenceAtIndex:*caret];
            [field deleteCharactersInRange:next];
            if (!_editingReplacement)
                [self.delegate searchPopoverDidChange:self];
        }
        self.needsDisplay = YES;
        return;
    }
    if (event.keyCode == 123 || event.keyCode == 124) {
        *selected = NO;
        if (command) {
            *caret = event.keyCode == 123 ? 0 : field.length;
        } else if (event.keyCode == 123 && *caret > 0) {
            *caret = [field rangeOfComposedCharacterSequenceAtIndex:*caret - 1].location;
        } else if (event.keyCode == 124 && *caret < field.length) {
            *caret = NSMaxRange([field rangeOfComposedCharacterSequenceAtIndex:*caret]);
        }
        self.needsDisplay = YES;
        return;
    }
    if (event.keyCode == 125 || event.keyCode == 126) {
        if (_results.count > 0) {
            NSInteger step = event.keyCode == 125 ? 1 : -1;
            _selectedResult = MIN((NSInteger)_results.count - 1, MAX(0, _selectedResult + step));
            NSRect row = [self resultRectAtIndex:(NSUInteger)_selectedResult];
            if (NSMaxY(row) > NSHeight(self.bounds) - 8.0) {
                _scrollOffset += NSMaxY(row) - (NSHeight(self.bounds) - 8.0);
            } else if (NSMinY(row) < [self resultsY]) {
                _scrollOffset -= [self resultsY] - NSMinY(row);
            }
            _scrollOffset = MIN([self maximumScroll], MAX(0.0, _scrollOffset));
            self.needsDisplay = YES;
        }
        return;
    }
    if (event.keyCode == 36 || event.keyCode == 76) {
        if (_editingReplacement && _scope == KineticSearchScopeFile && _results.count > 0) {
            [self.delegate searchPopover:self didRequestReplaceResult:_results[0]];
            return;
        }
        if (_selectedResult >= 0 && _selectedResult < (NSInteger)_results.count) {
            [self.delegate searchPopover:self
                         didSelectResult:_results[(NSUInteger)_selectedResult]];
        }
        return;
    }
    if (command) {
        [super keyDown:event];
        return;
    }
    NSString* characters = event.characters;
    if (characters.length > 0 && [characters characterAtIndex:0] >= 0x20) {
        [self replaceSelectionWithText:characters];
    }
}

@end
