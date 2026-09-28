#import "commandPalette.h"
#import "theme.h"

namespace {
NSColor* paletteColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha = 1.0) {
    return kineticThemeColor(red, green, blue, alpha);
}
} // namespace

@interface KineticCommandPalette () <NSTextFieldDelegate> {
    NSTextField* _queryField;
    NSTrackingArea* _trackingArea;
    NSInteger _selectedIndex;
    NSInteger _hoveredIndex;
}
@end

@implementation KineticCommandPalette

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _commands = @[];
        _selectedIndex = 0;
        _hoveredIndex = -1;
        _queryField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _queryField.placeholderString = @"Type a command…";
        _queryField.font = [NSFont systemFontOfSize:15.0];
        _queryField.textColor = paletteColor(232, 239, 249);
        _queryField.backgroundColor = NSColor.clearColor;
        _queryField.drawsBackground = NO;
        _queryField.bordered = NO;
        _queryField.focusRingType = NSFocusRingTypeNone;
        _queryField.delegate = self;
        [self addSubview:_queryField];
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (NSRect)panelRect {
    CGFloat width = MIN(580.0, NSWidth(self.bounds) - 40.0);
    return NSMakeRect(floor((NSWidth(self.bounds) - width) * 0.5), 72.0, width, 344.0);
}

- (void)layout {
    [super layout];
    NSRect panel = [self panelRect];
    _queryField.frame =
        NSMakeRect(NSMinX(panel) + 22.0, NSMinY(panel) + 19.0, NSWidth(panel) - 44.0, 25.0);
}

- (void)focusQuery {
    [self.window makeFirstResponder:_queryField];
}

- (NSArray<NSDictionary<NSString*, NSString*>*>*)filteredCommands {
    NSString* query = [_queryField.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (query.length == 0) {
        return [_commands subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)9, _commands.count))];
    }
    NSMutableArray* result = [NSMutableArray array];
    for (NSDictionary<NSString*, NSString*>* command in _commands) {
        NSString* title = command[@"title"] ?: @"";
        NSString* category = command[@"category"] ?: @"";
        if ([title rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [category rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [result addObject:command];
            if (result.count == 9) {
                break;
            }
        }
    }
    return result;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [paletteColor(8, 13, 21, 0.58) setFill];
    NSRectFill(self.bounds);
    NSRect panel = [self panelRect];
    [paletteColor(39, 49, 64) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:panel xRadius:8.0 yRadius:8.0] fill];
    [paletteColor(82, 102, 130, 0.9) setStroke];
    [[NSBezierPath bezierPathWithRoundedRect:panel xRadius:8.0 yRadius:8.0] stroke];
    [paletteColor(69, 84, 105, 0.7) setFill];
    NSRectFillUsingOperation(
        NSMakeRect(NSMinX(panel) + 1.0, NSMinY(panel) + 61.0, NSWidth(panel) - 2.0, 1.0),
        NSCompositingOperationSourceOver);
    NSArray* filtered = [self filteredCommands];
    NSDictionary* titleStyle = @{
        NSFontAttributeName : [NSFont systemFontOfSize:13.0],
        NSForegroundColorAttributeName : paletteColor(227, 235, 247),
    };
    NSDictionary* detailStyle = @{
        NSFontAttributeName : [NSFont systemFontOfSize:11.0],
        NSForegroundColorAttributeName : paletteColor(148, 165, 189),
    };
    for (NSUInteger index = 0; index < filtered.count; ++index) {
        CGFloat y = NSMinY(panel) + 66.0 + index * 30.0;
        if ((NSInteger)index == _selectedIndex || (NSInteger)index == _hoveredIndex) {
            [paletteColor(66, 89, 125, 0.67) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMinX(panel) + 7.0, y,
                                                                NSWidth(panel) - 14.0, 28.0)
                                             xRadius:4.0
                                             yRadius:4.0] fill];
        }
        NSDictionary* command = filtered[index];
        [command[@"title"]
                drawInRect:NSMakeRect(NSMinX(panel) + 19.0, y + 5.0, NSWidth(panel) - 160.0, 20.0)
            withAttributes:titleStyle];
        NSString* shortcut = command[@"shortcut"] ?: @"";
        NSSize shortcutSize = [shortcut sizeWithAttributes:detailStyle];
        [shortcut drawAtPoint:NSMakePoint(NSMaxX(panel) - shortcutSize.width - 22.0, y + 6.0)
               withAttributes:detailStyle];
    }
    if (filtered.count == 0) {
        [@"No matching commands" drawAtPoint:NSMakePoint(NSMinX(panel) + 20.0, NSMinY(panel) + 80.0)
                              withAttributes:detailStyle];
    }
}

- (void)runSelected {
    NSArray* filtered = [self filteredCommands];
    if (_selectedIndex >= 0 && _selectedIndex < (NSInteger)filtered.count) {
        [self.delegate commandPalette:self
                     didChooseCommand:filtered[(NSUInteger)_selectedIndex][@"id"]];
    }
}

- (void)controlTextDidChange:(NSNotification*)notification {
    (void)notification;
    _selectedIndex = 0;
    self.needsDisplay = YES;
}

- (BOOL)control:(NSControl*)control
               textView:(NSTextView*)textView
    doCommandBySelector:(SEL)selector {
    (void)control;
    (void)textView;
    if (selector == @selector(cancelOperation:)) {
        [self.delegate commandPaletteDidClose:self];
    } else if (selector == @selector(insertNewline:)) {
        [self runSelected];
    } else if (selector == @selector(moveDown:)) {
        _selectedIndex = MIN(_selectedIndex + 1, (NSInteger)[self filteredCommands].count - 1);
        self.needsDisplay = YES;
    } else if (selector == @selector(moveUp:)) {
        _selectedIndex = MAX(0, _selectedIndex - 1);
        self.needsDisplay = YES;
    } else {
        return NO;
    }
    return YES;
}

- (void)mouseMoved:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect panel = [self panelRect];
    NSInteger index = (NSInteger)floor((point.y - NSMinY(panel) - 66.0) / 30.0);
    NSInteger hovered = point.x >= NSMinX(panel) && point.x <= NSMaxX(panel) &&
                                point.y >= NSMinY(panel) + 66.0 &&
                                index < (NSInteger)[self filteredCommands].count
                            ? index
                            : -1;
    if (_hoveredIndex != hovered) {
        _hoveredIndex = hovered;
        self.needsDisplay = YES;
    }
}

- (void)updateTrackingAreas {
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
                     NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
               owner:self
            userInfo:nil];
    [self addTrackingArea:_trackingArea];
    [super updateTrackingAreas];
}

- (void)mouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(point, [self panelRect])) {
        [self.delegate commandPaletteDidClose:self];
        return;
    }
    if (_hoveredIndex >= 0) {
        _selectedIndex = _hoveredIndex;
        [self runSelected];
    } else {
        [self focusQuery];
    }
}

@end
