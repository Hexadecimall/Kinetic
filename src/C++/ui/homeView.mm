#import "homeView.h"

namespace {

constexpr CGFloat kContentWidth = 620.0;
constexpr CGFloat kColumnGap = 54.0;
constexpr CGFloat kColumnWidth = (kContentWidth - kColumnGap) * 0.5;
constexpr CGFloat kActionHeight = 34.0;

NSColor* homeColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha = 1.0) {
    return [NSColor colorWithSRGBRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:alpha];
}

} // namespace

@interface KineticHomeView () {
    NSArray<NSString*>* _actionTitles;
    NSMutableArray<NSValue*>* _actionRects;
    NSMutableArray<NSValue*>* _recentRects;
    NSTrackingArea* _trackingArea;
    NSInteger _hoveredAction;
    NSInteger _hoveredRecent;
}
@end

@implementation KineticHomeView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _actionTitles = @[ @"New Text File", @"Open File…", @"Open Folder…" ];
        _actionRects = [[NSMutableArray alloc] init];
        _recentRects = [[NSMutableArray alloc] init];
        _recentProjects = @[];
        _hoveredAction = -1;
        _hoveredRecent = -1;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    }
    return self;
}

- (void)setRecentProjects:(NSArray<NSURL*>*)recentProjects {
    _recentProjects = [recentProjects copy];
    self.needsDisplay = YES;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return NO;
}

- (CGFloat)contentX {
    return MAX(48.0, floor((NSWidth(self.bounds) - kContentWidth) * 0.5));
}

- (CGFloat)contentY {
    return MAX(84.0, floor((NSHeight(self.bounds) - 430.0) * 0.34));
}

- (void)rebuildActionRects {
    [_actionRects removeAllObjects];
    CGFloat x = [self contentX];
    CGFloat y = [self contentY] + 106.0;
    for (NSUInteger index = 0; index < _actionTitles.count; ++index) {
        [_actionRects
            addObject:[NSValue valueWithRect:NSMakeRect(x, y, kColumnWidth, kActionHeight)]];
        y += kActionHeight + 4.0;
    }
}

- (void)rebuildRecentRects {
    [_recentRects removeAllObjects];
    CGFloat x = [self contentX] + kColumnWidth + kColumnGap;
    CGFloat y = [self contentY] + 106.0;
    NSUInteger count = MIN((NSUInteger)6, _recentProjects.count);
    for (NSUInteger index = 0; index < count; ++index) {
        [_recentRects addObject:[NSValue valueWithRect:NSMakeRect(x, y, kColumnWidth, 42.0)]];
        y += 46.0;
    }
}

- (void)drawActionIconAtIndex:(NSUInteger)index inRect:(NSRect)rect color:(NSColor*)color {
    const CGFloat x = NSMinX(rect) + 9.0;
    const CGFloat y = NSMidY(rect) - 6.0;
    NSBezierPath* icon = [NSBezierPath bezierPath];
    icon.lineWidth = 1.25;
    icon.lineCapStyle = NSLineCapStyleRound;
    icon.lineJoinStyle = NSLineJoinStyleRound;

    if (index == 0) {
        [icon appendBezierPathWithRect:NSMakeRect(x + 2.0, y, 9.0, 12.0)];
        [icon moveToPoint:NSMakePoint(x + 4.0, y + 4.0)];
        [icon lineToPoint:NSMakePoint(x + 9.0, y + 4.0)];
        [icon moveToPoint:NSMakePoint(x + 4.0, y + 7.0)];
        [icon lineToPoint:NSMakePoint(x + 9.0, y + 7.0)];
    } else if (index == 1) {
        [icon appendBezierPathWithRoundedRect:NSMakeRect(x + 1.0, y, 11.0, 12.0)
                                      xRadius:1.5
                                      yRadius:1.5];
        [icon moveToPoint:NSMakePoint(x + 4.0, y + 4.0)];
        [icon lineToPoint:NSMakePoint(x + 9.0, y + 4.0)];
    } else {
        [icon moveToPoint:NSMakePoint(x, y + 3.0)];
        [icon lineToPoint:NSMakePoint(x + 5.0, y + 3.0)];
        [icon lineToPoint:NSMakePoint(x + 7.0, y + 1.0)];
        [icon lineToPoint:NSMakePoint(x + 13.0, y + 1.0)];
        [icon lineToPoint:NSMakePoint(x + 13.0, y + 11.0)];
        [icon lineToPoint:NSMakePoint(x, y + 11.0)];
        [icon closePath];
    }

    [color setStroke];
    [icon stroke];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [homeColor(47, 57, 71, 0.9) setFill];
    NSRectFill(self.bounds);
    [self rebuildActionRects];
    [self rebuildRecentRects];

    CGFloat x = [self contentX];
    CGFloat y = [self contentY];

    NSGradient* blueGlow = [[NSGradient alloc] initWithStartingColor:homeColor(77, 141, 255, 0.08)
                                                         endingColor:homeColor(77, 141, 255, 0.0)];
    [blueGlow drawFromCenter:NSMakePoint(x + 86.0, y + 18.0)
                      radius:0.0
                    toCenter:NSMakePoint(x + 86.0, y + 18.0)
                      radius:310.0
                     options:0];
    NSGradient* orangeGlow =
        [[NSGradient alloc] initWithStartingColor:homeColor(255, 122, 61, 0.045)
                                      endingColor:homeColor(255, 122, 61, 0.0)];
    [orangeGlow drawFromCenter:NSMakePoint(x + 22.0, y + 22.0)
                        radius:0.0
                      toCenter:NSMakePoint(x + 22.0, y + 22.0)
                        radius:185.0
                       options:0];

    NSImage* appIcon = NSApp.applicationIconImage;
    [appIcon drawInRect:NSMakeRect(x, y - 5.0, 44.0, 44.0)
               fromRect:NSZeroRect
              operation:NSCompositingOperationSourceOver
               fraction:1.0
         respectFlipped:YES
                  hints:nil];

    NSDictionary* titleAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:30.0 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName : homeColor(235, 240, 247),
    };
    [@"Kinetic" drawAtPoint:NSMakePoint(x + 56.0, y) withAttributes:titleAttributes];

    NSDictionary* headingAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName : homeColor(218, 225, 235),
    };
    [@"Start" drawAtPoint:NSMakePoint(x, y + 76.0) withAttributes:headingAttributes];

    NSDictionary* actionAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : homeColor(204, 218, 236),
    };
    for (NSUInteger index = 0; index < _actionTitles.count; ++index) {
        NSRect rect = _actionRects[index].rectValue;
        [homeColor(53, 64, 79, 0.78) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:3.0 yRadius:3.0] fill];
        if (_hoveredAction == (NSInteger)index) {
            [homeColor(77, 141, 255, 0.18) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:3.0 yRadius:3.0] fill];
        }
        [self drawActionIconAtIndex:index inRect:rect color:homeColor(112, 166, 255)];
        NSSize textSize = [_actionTitles[index] sizeWithAttributes:actionAttributes];
        [_actionTitles[index]
               drawAtPoint:NSMakePoint(NSMinX(rect) + 31.0, NSMidY(rect) - textSize.height * 0.5)
            withAttributes:actionAttributes];
    }

    CGFloat rightX = x + kColumnWidth + kColumnGap;
    [@"Recent" drawAtPoint:NSMakePoint(rightX, y + 76.0) withAttributes:headingAttributes];
    if (_recentProjects.count == 0) {
        NSRect emptyRect = NSMakeRect(rightX, y + 106.0, kColumnWidth, 58.0);
        [homeColor(53, 64, 79, 0.58) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:emptyRect xRadius:3.0 yRadius:3.0] fill];

        NSPoint clockCenter = NSMakePoint(NSMinX(emptyRect) + 22.0, NSMidY(emptyRect));
        NSBezierPath* clock =
            [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(clockCenter.x - 7.0,
                                                              clockCenter.y - 7.0, 14.0, 14.0)];
        [clock moveToPoint:clockCenter];
        [clock lineToPoint:NSMakePoint(clockCenter.x, clockCenter.y - 4.0)];
        [clock moveToPoint:clockCenter];
        [clock lineToPoint:NSMakePoint(clockCenter.x + 3.5, clockCenter.y + 1.5)];
        clock.lineWidth = 1.15;
        clock.lineCapStyle = NSLineCapStyleRound;
        [homeColor(122, 139, 160) setStroke];
        [clock stroke];

        NSDictionary* emptyAttributes = @{
            NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName : homeColor(148, 161, 178),
        };
        [@"No recent projects" drawAtPoint:NSMakePoint(rightX + 41.0, y + 125.0)
                            withAttributes:emptyAttributes];
    } else {
        NSMutableParagraphStyle* truncatingStyle = [[NSMutableParagraphStyle alloc] init];
        truncatingStyle.lineBreakMode = NSLineBreakByTruncatingMiddle;
        NSDictionary* recentTitleAttributes = @{
            NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName : homeColor(215, 226, 240),
        };
        NSDictionary* recentPathAttributes = @{
            NSFontAttributeName : [NSFont systemFontOfSize:9.5 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName : homeColor(132, 146, 166),
            NSParagraphStyleAttributeName : truncatingStyle,
        };
        for (NSUInteger index = 0; index < _recentRects.count; ++index) {
            NSRect rect = _recentRects[index].rectValue;
            [homeColor(53, 64, 79, _hoveredRecent == (NSInteger)index ? 0.94 : 0.58) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:3.0 yRadius:3.0] fill];
            if (_hoveredRecent == (NSInteger)index) {
                [homeColor(77, 141, 255, 0.16) setFill];
                [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:3.0 yRadius:3.0] fill];
            }
            [self drawActionIconAtIndex:2 inRect:rect color:homeColor(112, 166, 255)];
            NSURL* projectUrl = _recentProjects[index];
            [projectUrl.lastPathComponent
                   drawAtPoint:NSMakePoint(NSMinX(rect) + 31.0, NSMinY(rect) + 6.0)
                withAttributes:recentTitleAttributes];
            [projectUrl.path.stringByDeletingLastPathComponent
                    drawInRect:NSMakeRect(NSMinX(rect) + 31.0, NSMinY(rect) + 23.0,
                                          NSWidth(rect) - 40.0, 14.0)
                withAttributes:recentPathAttributes];
        }
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

- (void)mouseMoved:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger hovered = -1;
    for (NSUInteger index = 0; index < _actionRects.count; ++index) {
        if (NSPointInRect(point, _actionRects[index].rectValue)) {
            hovered = (NSInteger)index;
            break;
        }
    }
    NSInteger hoveredRecent = -1;
    for (NSUInteger index = 0; index < _recentRects.count; ++index) {
        if (NSPointInRect(point, _recentRects[index].rectValue)) {
            hoveredRecent = (NSInteger)index;
            break;
        }
    }
    if (hovered != _hoveredAction) {
        _hoveredAction = hovered;
        self.needsDisplay = YES;
    }
    if (hoveredRecent != _hoveredRecent) {
        _hoveredRecent = hoveredRecent;
        self.needsDisplay = YES;
    }
}

- (void)mouseExited:(NSEvent*)event {
    (void)event;
    _hoveredAction = -1;
    _hoveredRecent = -1;
    self.needsDisplay = YES;
}

- (void)mouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    for (NSUInteger index = 0; index < _actionRects.count; ++index) {
        if (!NSPointInRect(point, _actionRects[index].rectValue)) {
            continue;
        }
        if (index == 0) {
            [self.commandHandler newTextFile];
        } else if (index == 1) {
            [self.commandHandler openFile];
        } else if (index == 2) {
            [self.commandHandler openFolder];
        }
        return;
    }
    for (NSUInteger index = 0; index < _recentRects.count; ++index) {
        if (NSPointInRect(point, _recentRects[index].rectValue)) {
            [self.commandHandler openRecentProjectAtUrl:_recentProjects[index]];
            return;
        }
    }
}

@end
