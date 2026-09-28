#import "searchPopover.h"
#import "contextMenu.h"
#import "theme.h"

namespace {

constexpr CGFloat kResultsY = 151.0;
constexpr CGFloat kResultHeight = 44.0;

NSColor* searchColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha = 1.0) {
    return kineticThemeColor(red, green, blue, alpha);
}

} // namespace

@interface KineticSearchPopover () {
    NSMutableString* _query;
    NSArray<NSDictionary*>* _results;
    NSUInteger _caretIndex;
    NSInteger _selectedResult;
    NSInteger _hoveredResult;
    CGFloat _scrollOffset;
    BOOL _selectAll;
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
    [self.window makeFirstResponder:self];
    self.needsDisplay = YES;
}

- (CGFloat)preferredHeight {
    if (_query.length == 0 || _results.count == 0) {
        return 165.0;
    }
    return 159.0 + MIN((NSUInteger)5, _results.count) * kResultHeight;
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

- (NSRect)resultRectAtIndex:(NSUInteger)index {
    return NSMakeRect(7.0, kResultsY + index * kResultHeight - _scrollOffset,
                      NSWidth(self.bounds) - 14.0, kResultHeight);
}

- (CGFloat)maximumScroll {
    return MAX(0.0,
               _results.count * kResultHeight - MAX(1.0, NSHeight(self.bounds) - kResultsY - 8.0));
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
    [searchColor(self.window.firstResponder == self ? 77 : 75,
                 self.window.firstResponder == self ? 141 : 89,
                 self.window.firstResponder == self ? 255 : 109, 0.72) setStroke];
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
    if (self.window.firstResponder == self && !_selectAll) {
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
    [status drawAtPoint:NSMakePoint(16.0, 126.0)
         withAttributes:@{
             NSFontAttributeName : [NSFont systemFontOfSize:11.0],
             NSForegroundColorAttributeName : searchColor(142, 158, 180),
         }];

    NSRect clip = NSMakeRect(2.0, kResultsY, NSWidth(self.bounds) - 4.0,
                             MAX(0.0, NSHeight(self.bounds) - kResultsY - 3.0));
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
    for (NSUInteger index = 0; point.y >= kResultsY && index < _results.count; ++index) {
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
    } else if (NSPointInRect(point, [self queryRect])) {
        _selectAll = NO;
        _caretIndex = _query.length;
        [self focusQuery];
    } else {
        for (NSUInteger index = 0; point.y >= kResultsY && index < _results.count; ++index) {
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
    if (!NSPointInRect(point, [self queryRect])) {
        return;
    }
    NSString* pasted = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
    [KineticContextMenu
        showInView:self
           atPoint:point
             items:@[
                 @{@"title" : @"Copy Query", @"enabled" : @(_query.length > 0)},
                 @{@"title" : @"Paste", @"enabled" : @(pasted.length > 0)},
                 @{@"title" : @"Select All", @"enabled" : @(_query.length > 0)},
                 @{@"title" : @"Clear", @"enabled" : @(_query.length > 0)}
             ]
           handler:^(NSUInteger index) {
             if (index == 0) {
                 [NSPasteboard.generalPasteboard clearContents];
                 [NSPasteboard.generalPasteboard setString:_query forType:NSPasteboardTypeString];
             } else if (index == 1) {
                 NSString* oneLine = [[pasted
                     componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]
                     componentsJoinedByString:@" "];
                 [self replaceSelectionWithText:oneLine];
             } else if (index == 2) {
                 _selectAll = YES;
                 self.needsDisplay = YES;
             } else {
                 _selectAll = YES;
                 [self replaceSelectionWithText:@""];
             }
           }];
}

- (void)scrollWheel:(NSEvent*)event {
    _scrollOffset = MIN([self maximumScroll], MAX(0.0, _scrollOffset - event.scrollingDeltaY));
    self.needsDisplay = YES;
}

- (void)replaceSelectionWithText:(NSString*)text {
    if (_selectAll) {
        [_query setString:@""];
        _caretIndex = 0;
        _selectAll = NO;
    }
    if (_query.length + text.length > 200) {
        return;
    }
    [_query insertString:text atIndex:_caretIndex];
    _caretIndex += text.length;
    [self.delegate searchPopoverDidChange:self];
    self.needsDisplay = YES;
}

- (void)keyDown:(NSEvent*)event {
    BOOL command = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    NSString* key = event.charactersIgnoringModifiers.lowercaseString;
    if (event.keyCode == 53) {
        [self.delegate searchPopoverDidRequestClose:self];
        return;
    }
    if (command && [key isEqualToString:@"a"]) {
        _selectAll = YES;
        self.needsDisplay = YES;
        return;
    }
    if (command && ([key isEqualToString:@"c"] || [key isEqualToString:@"x"])) {
        if (_selectAll) {
            [NSPasteboard.generalPasteboard clearContents];
            [NSPasteboard.generalPasteboard setString:_query forType:NSPasteboardTypeString];
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
        if (_selectAll) {
            [self replaceSelectionWithText:@""];
        } else if (event.keyCode == 51 && _caretIndex > 0) {
            NSRange previous = [_query rangeOfComposedCharacterSequenceAtIndex:_caretIndex - 1];
            [_query deleteCharactersInRange:previous];
            _caretIndex = previous.location;
            [self.delegate searchPopoverDidChange:self];
        } else if (event.keyCode == 117 && _caretIndex < _query.length) {
            NSRange next = [_query rangeOfComposedCharacterSequenceAtIndex:_caretIndex];
            [_query deleteCharactersInRange:next];
            [self.delegate searchPopoverDidChange:self];
        }
        self.needsDisplay = YES;
        return;
    }
    if (event.keyCode == 123 || event.keyCode == 124) {
        _selectAll = NO;
        if (command) {
            _caretIndex = event.keyCode == 123 ? 0 : _query.length;
        } else if (event.keyCode == 123 && _caretIndex > 0) {
            _caretIndex = [_query rangeOfComposedCharacterSequenceAtIndex:_caretIndex - 1].location;
        } else if (event.keyCode == 124 && _caretIndex < _query.length) {
            _caretIndex = NSMaxRange([_query rangeOfComposedCharacterSequenceAtIndex:_caretIndex]);
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
            } else if (NSMinY(row) < kResultsY) {
                _scrollOffset -= kResultsY - NSMinY(row);
            }
            _scrollOffset = MIN([self maximumScroll], MAX(0.0, _scrollOffset));
            self.needsDisplay = YES;
        }
        return;
    }
    if (event.keyCode == 36 || event.keyCode == 76) {
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
