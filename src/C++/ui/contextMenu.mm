#import "contextMenu.h"
#import "theme.h"

namespace {
constexpr CGFloat kMenuWidth = 196.0;
constexpr CGFloat kRowHeight = 27.0;
constexpr CGFloat kPadding = 7.0;

NSColor* menuColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha = 1.0) {
    return kineticThemeColor(red, green, blue, alpha);
}
} // namespace

@interface KineticContextMenu () {
    NSArray<NSDictionary<NSString*, id>*>* _items;
    void (^_handler)(NSUInteger index);
    NSRect _menuRect;
    NSInteger _hoveredIndex;
    NSTrackingArea* _trackingArea;
    __weak NSResponder* _previousResponder;
}
@end

@implementation KineticContextMenu

+ (void)showInView:(NSView*)view
           atPoint:(NSPoint)point
             items:(NSArray<NSDictionary<NSString*, id>*>*)items
           handler:(void (^)(NSUInteger index))handler {
    for (NSView* child in [view.subviews copy]) {
        if ([child isKindOfClass:KineticContextMenu.class]) {
            [(KineticContextMenu*)child dismiss];
        }
    }
    if (items.count == 0) {
        return;
    }
    KineticContextMenu* menu = [[KineticContextMenu alloc] initWithFrame:view.bounds];
    menu.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    menu->_items = [items copy];
    menu->_handler = [handler copy];
    menu->_hoveredIndex = -1;
    CGFloat height = kPadding * 2.0 + items.count * kRowHeight;
    CGFloat x = MAX(6.0, MIN(point.x, NSWidth(view.bounds) - kMenuWidth - 6.0));
    CGFloat y = MAX(6.0, MIN(point.y, NSHeight(view.bounds) - height - 6.0));
    menu->_menuRect = NSMakeRect(x, y, kMenuWidth, height);
    menu->_previousResponder = view.window.firstResponder;
    [view addSubview:menu positioned:NSWindowAbove relativeTo:nil];
    [view.window makeFirstResponder:menu];
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)dismiss {
    NSWindow* window = self.window;
    NSResponder* previous = _previousResponder;
    [self removeFromSuperview];
    if (previous != nil) {
        [window makeFirstResponder:previous];
    }
}

- (NSRect)rowRect:(NSUInteger)index {
    return NSMakeRect(NSMinX(_menuRect) + 5.0, NSMinY(_menuRect) + kPadding + index * kRowHeight,
                      NSWidth(_menuRect) - 10.0, kRowHeight);
}

- (NSInteger)rowAtPoint:(NSPoint)point {
    if (!NSPointInRect(point, _menuRect)) {
        return -1;
    }
    for (NSUInteger index = 0; index < _items.count; ++index) {
        if (NSPointInRect(point, [self rowRect:index])) {
            return (NSInteger)index;
        }
    }
    return -1;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSShadow* shadow = [[NSShadow alloc] init];
    shadow.shadowColor = menuColor(5, 9, 16, 0.55);
    shadow.shadowBlurRadius = 18.0;
    shadow.shadowOffset = NSMakeSize(0.0, 6.0);
    [NSGraphicsContext saveGraphicsState];
    [shadow set];
    [menuColor(35, 43, 55, 0.98) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:_menuRect xRadius:7.0 yRadius:7.0] fill];
    [NSGraphicsContext restoreGraphicsState];
    [menuColor(75, 90, 111, 0.75) setStroke];
    [[NSBezierPath bezierPathWithRoundedRect:_menuRect xRadius:7.0 yRadius:7.0] stroke];

    for (NSUInteger index = 0; index < _items.count; ++index) {
        NSDictionary* item = _items[index];
        BOOL enabled = item[@"enabled"] == nil || [item[@"enabled"] boolValue];
        NSRect row = [self rowRect:index];
        if (enabled && (NSInteger)index == _hoveredIndex) {
            [menuColor(77, 141, 255, 0.2) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:row xRadius:4.0 yRadius:4.0] fill];
        }
        NSColor* color = enabled ? menuColor(226, 233, 242) : menuColor(107, 119, 137);
        NSDictionary* attributes = @{
            NSFontAttributeName : [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName : color,
        };
        [item[@"title"] drawAtPoint:NSMakePoint(NSMinX(row) + 8.0, NSMinY(row) + 5.0)
                     withAttributes:attributes];
        NSString* shortcut = item[@"shortcut"];
        if (shortcut.length > 0) {
            NSSize size = [shortcut sizeWithAttributes:attributes];
            [shortcut drawAtPoint:NSMakePoint(NSMaxX(row) - size.width - 8.0, NSMinY(row) + 5.0)
                   withAttributes:attributes];
        }
    }
}

- (void)mouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger index = [self rowAtPoint:point];
    BOOL enabled = index >= 0 && (_items[(NSUInteger)index][@"enabled"] == nil ||
                                  [_items[(NSUInteger)index][@"enabled"] boolValue]);
    void (^handler)(NSUInteger) = _handler;
    [self dismiss];
    if (enabled) {
        handler((NSUInteger)index);
    }
}

- (void)rightMouseDown:(NSEvent*)event {
    [self mouseDown:event];
}

- (void)keyDown:(NSEvent*)event {
    if (event.keyCode == 53) {
        [self dismiss];
    } else {
        [super keyDown:event];
    }
}

- (void)updateTrackingAreas {
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
               owner:self
            userInfo:nil];
    [self addTrackingArea:_trackingArea];
    [super updateTrackingAreas];
}

- (void)mouseMoved:(NSEvent*)event {
    NSInteger index = [self rowAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (index != _hoveredIndex) {
        _hoveredIndex = index;
        self.needsDisplay = YES;
    }
}

- (void)resetCursorRects {
    [super resetCursorRects];
    [self addCursorRect:self.bounds cursor:NSCursor.arrowCursor];
}

@end
