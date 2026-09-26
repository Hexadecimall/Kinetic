#import "trafficBar.h"

namespace {

constexpr CGFloat kBarHeight = 34.0;
constexpr CGFloat kControlSize = 20.0;
constexpr CGFloat kControlGap = 4.0;
constexpr CGFloat kControlStart = 11.0;
constexpr CGFloat kMenuStart = 84.0;
constexpr NSInteger kNoHit = -1;
constexpr NSInteger kMenuHitBase = 100;
constexpr NSInteger kSearchHit = 200;

NSColor* color(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha = 1.0) {
    return [NSColor colorWithSRGBRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:alpha];
}

} // namespace

@class KineticTrafficBar;

@interface KineticTrafficBar (MenuControl)
- (void)closeMenu;
@end

@interface KineticMenuOverlay : NSView {
    KineticTrafficBar* _owner;
    NSArray<NSString*>* _titles;
    NSArray<NSString*>* _shortcuts;
    NSMutableArray<NSValue*>* _rowRects;
    NSTrackingArea* _trackingArea;
    NSInteger _hoveredRow;
    NSInteger _selectedRow;
    NSRect _menuFrame;
}
- (instancetype)initWithFrame:(NSRect)frame owner:(KineticTrafficBar*)owner;
@end

@implementation KineticMenuOverlay

- (instancetype)initWithFrame:(NSRect)frame owner:(KineticTrafficBar*)owner {
    self = [super initWithFrame:frame];
    if (self) {
        _owner = owner;
        _titles = @[ @"New File", @"Open File…", @"Open Folder…", @"", @"Save", @"", @"Close Tab" ];
        _shortcuts = @[ @"⌘N", @"⌘O", @"", @"", @"⌘S", @"", @"⌘W" ];
        _rowRects = [[NSMutableArray alloc] init];
        _hoveredRow = kNoHit;
        _selectedRow = 0;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

- (BOOL)isCommandEnabledAtIndex:(NSInteger)index {
    return index == 0 || index == 1 || index == 2 || index == 4 || index == 6;
}

- (BOOL)isSeparatorAtIndex:(NSInteger)index {
    return _titles[(NSUInteger)index].length == 0;
}

- (void)rebuildRows {
    [_rowRects removeAllObjects];
    CGFloat y = kBarHeight + 3.0;
    const CGFloat width = 216.0;
    for (NSUInteger index = 0; index < _titles.count; ++index) {
        const CGFloat height = [self isSeparatorAtIndex:(NSInteger)index] ? 9.0 : 25.0;
        [_rowRects addObject:[NSValue valueWithRect:NSMakeRect(kMenuStart, y, width, height)]];
        y += height;
    }
    _menuFrame = NSMakeRect(kMenuStart, kBarHeight + 3.0, width, y - kBarHeight - 3.0);
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [self rebuildRows];

    NSShadow* shadow = [[NSShadow alloc] init];
    shadow.shadowColor = color(9, 13, 20, 0.42);
    shadow.shadowBlurRadius = 12.0;
    shadow.shadowOffset = NSMakeSize(0.0, -3.0);
    [NSGraphicsContext saveGraphicsState];
    [shadow set];
    [color(47, 59, 76) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:_menuFrame xRadius:4.0 yRadius:4.0] fill];
    [NSGraphicsContext restoreGraphicsState];

    [color(78, 94, 115) setStroke];
    NSBezierPath* border = [NSBezierPath bezierPathWithRoundedRect:_menuFrame
                                                           xRadius:4.0
                                                           yRadius:4.0];
    border.lineWidth = 1.0;
    [border stroke];

    NSDictionary* enabledAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : color(226, 232, 241),
    };
    NSDictionary* disabledAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : color(132, 144, 161),
    };
    NSDictionary* shortcutAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : color(155, 167, 184),
    };

    for (NSUInteger index = 0; index < _titles.count; ++index) {
        NSRect row = _rowRects[index].rectValue;
        if ([self isSeparatorAtIndex:(NSInteger)index]) {
            [color(73, 87, 106) setFill];
            NSRectFill(NSMakeRect(NSMinX(row) + 8.0, NSMidY(row), NSWidth(row) - 16.0, 1.0));
            continue;
        }

        const BOOL enabled = [self isCommandEnabledAtIndex:(NSInteger)index];
        if (enabled && (_hoveredRow == (NSInteger)index || _selectedRow == (NSInteger)index)) {
            [color(77, 141, 255, 0.2) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(row, 4.0, 2.0)
                                             xRadius:3.0
                                             yRadius:3.0] fill];
        }

        NSString* title = _titles[index];
        NSDictionary* attributes = enabled ? enabledAttributes : disabledAttributes;
        NSSize titleSize = [title sizeWithAttributes:attributes];
        [title drawAtPoint:NSMakePoint(NSMinX(row) + 12.0, NSMidY(row) - titleSize.height * 0.5)
            withAttributes:attributes];

        NSString* shortcut = _shortcuts[index];
        NSSize shortcutSize = [shortcut sizeWithAttributes:shortcutAttributes];
        [shortcut drawAtPoint:NSMakePoint(NSMaxX(row) - shortcutSize.width - 12.0,
                                          NSMidY(row) - shortcutSize.height * 0.5)
               withAttributes:shortcutAttributes];
    }
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

- (NSInteger)rowAtPoint:(NSPoint)point {
    for (NSUInteger index = 0; index < _rowRects.count; ++index) {
        if (![self isSeparatorAtIndex:(NSInteger)index] &&
            NSPointInRect(point, _rowRects[index].rectValue)) {
            return (NSInteger)index;
        }
    }
    return kNoHit;
}

- (void)mouseMoved:(NSEvent*)event {
    NSInteger row = [self rowAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (row != _hoveredRow) {
        _hoveredRow = row;
        if ([self isCommandEnabledAtIndex:row]) {
            _selectedRow = row;
        }
        self.needsDisplay = YES;
    }
}

- (void)mouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger row = [self rowAtPoint:point];
    if (row == 0) {
        [_owner closeMenu];
        [_owner.commandHandler newTextFile];
    } else if (row == 1) {
        [_owner closeMenu];
        [_owner.commandHandler openFile];
    } else if (row == 2) {
        [_owner closeMenu];
        [_owner.commandHandler openFolder];
    } else if (row == 4) {
        [_owner closeMenu];
        [_owner.commandHandler saveFile];
    } else if (row == 6) {
        [_owner closeMenu];
        if (![_owner.commandHandler closeActiveTab]) {
            [self.window performClose:nil];
        }
    } else if (!NSPointInRect(point, _menuFrame)) {
        [_owner closeMenu];
    }
}

- (void)keyDown:(NSEvent*)event {
    if (event.keyCode == 53) {
        [_owner closeMenu];
    } else if (event.keyCode == 36 && _selectedRow == 0) {
        [_owner closeMenu];
        [_owner.commandHandler newTextFile];
    } else if (event.keyCode == 36 && _selectedRow == 1) {
        [_owner closeMenu];
        [_owner.commandHandler openFile];
    } else if (event.keyCode == 36 && _selectedRow == 2) {
        [_owner closeMenu];
        [_owner.commandHandler openFolder];
    } else if (event.keyCode == 36 && _selectedRow == 4) {
        [_owner closeMenu];
        [_owner.commandHandler saveFile];
    } else if (event.keyCode == 36 && _selectedRow == 6) {
        [_owner closeMenu];
        if (![_owner.commandHandler closeActiveTab]) {
            [self.window performClose:nil];
        }
    } else {
        [super keyDown:event];
    }
}

@end

@interface KineticTrafficBar () {
    NSArray<NSString*>* _menuTitles;
    NSMutableArray<NSValue*>* _menuRects;
    NSTrackingArea* _trackingArea;
    KineticMenuOverlay* _menuOverlay;
    NSInteger _hoveredItem;
    BOOL _menuOpen;
}
@end

@implementation KineticTrafficBar

+ (CGFloat)preferredHeight {
    return kBarHeight;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _menuTitles = @[ @"File" ];
        _menuRects = [[NSMutableArray alloc] init];
        _hoveredItem = kNoHit;
        _menuOpen = NO;
        self.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

- (BOOL)isOpaque {
    return NO;
}

- (void)setShowsSearch:(BOOL)showsSearch {
    _showsSearch = showsSearch;
    if (!showsSearch && _hoveredItem == kSearchHit) {
        _hoveredItem = kNoHit;
    }
    self.needsDisplay = YES;
}

- (void)setSearchActive:(BOOL)searchActive {
    _searchActive = searchActive;
    self.needsDisplay = YES;
}

- (NSRect)searchButtonRect {
    return NSMakeRect(NSWidth(self.bounds) - 43.0, 3.0, 34.0, kBarHeight - 6.0);
}

- (NSRect)controlRectAtIndex:(NSInteger)index {
    const CGFloat x = kControlStart + index * (kControlSize + kControlGap);
    const CGFloat y = (NSHeight(self.bounds) - kControlSize) * 0.5 + 2.0;
    return NSMakeRect(x, y, kControlSize, kControlSize);
}

- (NSDictionary<NSAttributedStringKey, id>*)menuTextAttributes {
    return @{
        NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : color(218, 225, 235),
    };
}

- (void)rebuildMenuRects {
    [_menuRects removeAllObjects];
    NSDictionary* attributes = [self menuTextAttributes];
    CGFloat x = kMenuStart;
    for (NSString* title in _menuTitles) {
        const CGFloat width = ceil([title sizeWithAttributes:attributes].width) + 14.0;
        [_menuRects addObject:[NSValue valueWithRect:NSMakeRect(x, 4.0, width, kBarHeight - 8.0)]];
        x += width + 1.0;
    }
}

- (void)drawControlAtIndex:(NSInteger)index {
    NSRect rect = [self controlRectAtIndex:index];
    const BOOL hovered = _hoveredItem == index;

    NSColor* fill = color(47, 57, 71);
    NSColor* stroke = color(73, 87, 106);
    NSColor* glyph = color(190, 201, 215);
    if (hovered) {
        if (index == 0) {
            fill = color(255, 122, 61);
        } else if (index == 1) {
            fill = color(77, 141, 255);
        } else {
            fill = color(77, 141, 255);
        }
        stroke = fill;
        glyph = color(245, 248, 252);
    }

    NSBezierPath* background = [NSBezierPath bezierPathWithRoundedRect:rect
                                                               xRadius:3.0
                                                               yRadius:3.0];
    [fill setFill];
    [background fill];
    [stroke setStroke];
    background.lineWidth = 1.0;
    [background stroke];

    const CGFloat centerX = NSMidX(rect);
    const CGFloat centerY = NSMidY(rect);
    NSBezierPath* icon = [NSBezierPath bezierPath];
    icon.lineWidth = 1.25;
    icon.lineCapStyle = NSLineCapStyleRound;
    icon.lineJoinStyle = NSLineJoinStyleRound;

    if (index == 0) {
        [icon moveToPoint:NSMakePoint(centerX - 3.0, centerY - 3.0)];
        [icon lineToPoint:NSMakePoint(centerX + 3.0, centerY + 3.0)];
        [icon moveToPoint:NSMakePoint(centerX + 3.0, centerY - 3.0)];
        [icon lineToPoint:NSMakePoint(centerX - 3.0, centerY + 3.0)];
    } else if (index == 1) {
        [icon moveToPoint:NSMakePoint(centerX - 3.25, centerY)];
        [icon lineToPoint:NSMakePoint(centerX + 3.25, centerY)];
    } else {
        NSRect zoomRect = NSMakeRect(centerX - 3.5, centerY - 3.5, 7.0, 7.0);
        [icon appendBezierPathWithRoundedRect:zoomRect xRadius:1.25 yRadius:1.25];
    }

    [glyph setStroke];
    [icon stroke];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    for (NSInteger index = 0; index < 3; ++index) {
        [self drawControlAtIndex:index];
    }

    [self rebuildMenuRects];
    NSDictionary* attributes = [self menuTextAttributes];
    for (NSUInteger index = 0; index < _menuTitles.count; ++index) {
        NSRect rect = _menuRects[index].rectValue;
        if (_menuOpen || _hoveredItem == kMenuHitBase + (NSInteger)index) {
            [color(77, 141, 255, 0.16) setFill];
            NSRect hoverRect = NSOffsetRect(rect, 0.0, -2.0);
            [[NSBezierPath bezierPathWithRoundedRect:hoverRect xRadius:3.0 yRadius:3.0] fill];
        }

        NSString* title = _menuTitles[index];
        NSSize size = [title sizeWithAttributes:attributes];
        NSPoint point = NSMakePoint(NSMinX(rect) + 7.0, NSMidY(rect) - size.height * 0.5);
        [title drawAtPoint:point withAttributes:attributes];
    }
    if (_showsSearch) {
        NSRect button = [self searchButtonRect];
        if (_searchActive || _hoveredItem == kSearchHit) {
            [color(77, 141, 255, _searchActive ? 0.19 : 0.10) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:button xRadius:5.0 yRadius:5.0] fill];
        }
        NSBezierPath* icon = [NSBezierPath bezierPath];
        icon.lineWidth = 1.35;
        [icon appendBezierPathWithOvalInRect:NSMakeRect(NSMidX(button) - 6.0, NSMidY(button) - 6.0,
                                                        10.0, 10.0)];
        [icon moveToPoint:NSMakePoint(NSMidX(button) + 2.5, NSMidY(button) + 2.5)];
        [icon lineToPoint:NSMakePoint(NSMidX(button) + 7.0, NSMidY(button) + 7.0)];
        [color(_searchActive ? 130 : 174, _searchActive ? 178 : 190, _searchActive ? 255 : 211)
            setStroke];
        [icon stroke];
    }
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

- (NSInteger)hitAtPoint:(NSPoint)point {
    if (_showsSearch && NSPointInRect(point, [self searchButtonRect])) {
        return kSearchHit;
    }
    for (NSInteger index = 0; index < 3; ++index) {
        if (NSPointInRect(point, [self controlRectAtIndex:index])) {
            return index;
        }
    }
    for (NSUInteger index = 0; index < _menuRects.count; ++index) {
        if (NSPointInRect(point, _menuRects[index].rectValue)) {
            return kMenuHitBase + (NSInteger)index;
        }
    }
    return kNoHit;
}

- (void)mouseMoved:(NSEvent*)event {
    NSInteger hovered = [self hitAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (hovered != _hoveredItem) {
        _hoveredItem = hovered;
        self.needsDisplay = YES;
    }
}

- (void)mouseExited:(NSEvent*)event {
    (void)event;
    _hoveredItem = kNoHit;
    self.needsDisplay = YES;
}

- (void)openMenu {
    if (_menuOpen) {
        [self closeMenu];
        return;
    }

    NSView* content = self.window.contentView;
    _menuOverlay = [[KineticMenuOverlay alloc] initWithFrame:content.bounds owner:self];
    [content addSubview:_menuOverlay positioned:NSWindowAbove relativeTo:nil];
    _menuOpen = YES;
    self.needsDisplay = YES;
    [self.window makeFirstResponder:_menuOverlay];
}

- (void)closeMenu {
    [_menuOverlay removeFromSuperview];
    _menuOverlay = nil;
    _menuOpen = NO;
    self.needsDisplay = YES;
    [self.window makeFirstResponder:self];
}

- (void)mouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger hit = [self hitAtPoint:point];
    if (hit == 0) {
        [self.window performClose:nil];
    } else if (hit == 1) {
        [self.window performMiniaturize:nil];
    } else if (hit == 2) {
        [self.window toggleFullScreen:nil];
    } else if (hit >= kMenuHitBase) {
        if (hit == kSearchHit) {
            [self.commandHandler toggleFileSearch];
            return;
        }
        [self openMenu];
    } else if (event.clickCount == 2) {
        [self.window performZoom:nil];
    } else {
        [self.window performWindowDragWithEvent:event];
    }
}

@end
