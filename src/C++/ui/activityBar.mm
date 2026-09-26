#import "activityBar.h"

#import "tween.h"

namespace {

constexpr CGFloat kRailWidth = 38.0;
constexpr CGFloat kPanelWidth = 224.0;
constexpr CGFloat kButtonSize = 30.0;
constexpr CGFloat kButtonGap = 5.0;
constexpr CGFloat kTreeRowHeight = 23.0;
constexpr CGFloat kTreeStartY = 218.0;

NSColor* activityColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha = 1.0) {
    return [NSColor colorWithSRGBRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:alpha];
}

} // namespace

@interface KineticActivityTreeEntry : NSObject
@property(nonatomic, strong) NSURL* url;
@property(nonatomic) NSUInteger depth;
@property(nonatomic) BOOL directory;
@end

@implementation KineticActivityTreeEntry
@end

@interface KineticActivityBar () {
    KineticActivitySection _activeSection;
    KineticActivitySection _displayedSection;
    KineticActivitySection _hoveredSection;
    NSTrackingArea* _trackingArea;
    NSMutableSet<NSString*>* _expandedPaths;
    NSArray<KineticActivityTreeEntry*>* _treeEntries;
    NSInteger _hoveredPanelAction;
    CGFloat _treeScrollOffset;
    BOOL _animating;
}
@end

@implementation KineticActivityBar

+ (CGFloat)railWidth {
    return kRailWidth;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _activeSection = KineticActivitySectionNone;
        _displayedSection = KineticActivitySectionNone;
        _hoveredSection = KineticActivitySectionNone;
        _documentTitle = @"Untitled-1";
        _expandedPaths = [NSMutableSet set];
        _treeEntries = @[];
        _hoveredPanelAction = -1;
        _treeScrollOffset = 0.0;
        _animating = NO;
        self.autoresizingMask = NSViewHeightSizable;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return NO;
}

- (KineticActivitySection)activeSection {
    return _activeSection;
}

- (void)deactivateSection {
    _activeSection = KineticActivitySectionNone;
    if (NSWidth(self.frame) <= kRailWidth + 0.5) {
        _displayedSection = KineticActivitySectionNone;
        _animating = NO;
        self.needsDisplay = YES;
        return;
    }

    _animating = YES;
    NSRect targetFrame = self.frame;
    targetFrame.size.width = kRailWidth;
    [KineticTween animateView:self
                      toFrame:targetFrame
                      toAlpha:1.0
                     duration:0.15
                   completion:^{
                     self->_displayedSection = KineticActivitySectionNone;
                     self->_animating = NO;
                     self.needsDisplay = YES;
                   }];
    self.needsDisplay = YES;
}

- (void)setDocumentTitle:(NSString*)documentTitle {
    _documentTitle = [documentTitle copy];
    self.needsDisplay = YES;
}

- (void)setWorkspaceUrl:(NSURL*)workspaceUrl {
    _workspaceUrl = workspaceUrl;
    [_expandedPaths removeAllObjects];
    [self reloadTreeEntries];
}

- (void)appendDirectory:(NSURL*)directory
                  depth:(NSUInteger)depth
              toEntries:(NSMutableArray<KineticActivityTreeEntry*>*)entries {
    if (depth > 12 || entries.count >= 500) {
        return;
    }
    NSArray<NSURL*>* urls = [NSFileManager.defaultManager
          contentsOfDirectoryAtURL:directory
        includingPropertiesForKeys:@[ NSURLIsDirectoryKey ]
                           options:NSDirectoryEnumerationSkipsHiddenFiles
                             error:nil];
    urls = [urls sortedArrayUsingComparator:^NSComparisonResult(NSURL* left, NSURL* right) {
      NSNumber* leftDirectory = nil;
      NSNumber* rightDirectory = nil;
      [left getResourceValue:&leftDirectory forKey:NSURLIsDirectoryKey error:nil];
      [right getResourceValue:&rightDirectory forKey:NSURLIsDirectoryKey error:nil];
      if (leftDirectory.boolValue != rightDirectory.boolValue) {
          return leftDirectory.boolValue ? NSOrderedAscending : NSOrderedDescending;
      }
      return [left.lastPathComponent localizedCaseInsensitiveCompare:right.lastPathComponent];
    }];
    for (NSURL* url in urls) {
        NSNumber* directoryValue = nil;
        [url getResourceValue:&directoryValue forKey:NSURLIsDirectoryKey error:nil];
        KineticActivityTreeEntry* entry = [[KineticActivityTreeEntry alloc] init];
        entry.url = url;
        entry.depth = depth;
        entry.directory = directoryValue.boolValue;
        [entries addObject:entry];
        if (entry.directory && [_expandedPaths containsObject:url.path]) {
            [self appendDirectory:url depth:depth + 1 toEntries:entries];
        }
        if (entries.count >= 500) {
            break;
        }
    }
}

- (void)reloadTreeEntries {
    if (_workspaceUrl == nil) {
        _treeEntries = @[];
    } else {
        NSMutableArray<KineticActivityTreeEntry*>* entries = [NSMutableArray array];
        [self appendDirectory:_workspaceUrl depth:0 toEntries:entries];
        _treeEntries = entries;
    }
    _treeScrollOffset = MIN(_treeScrollOffset, [self maximumTreeScroll]);
    self.needsDisplay = YES;
}

- (CGFloat)maximumTreeScroll {
    CGFloat viewportHeight = MAX(1.0, NSHeight(self.bounds) - kTreeStartY);
    return MAX(0.0, _treeEntries.count * kTreeRowHeight - viewportHeight);
}

- (NSRect)buttonRectForSection:(KineticActivitySection)section {
    if (section == KineticActivitySectionSettings) {
        return NSMakeRect(4.0, MAX(4.0, NSHeight(self.bounds) - kButtonSize - 6.0), kButtonSize,
                          kButtonSize);
    }
    return NSMakeRect(4.0, 7.0 + (NSInteger)section * (kButtonSize + kButtonGap), kButtonSize,
                      kButtonSize);
}

- (KineticActivitySection)sectionAtPoint:(NSPoint)point {
    for (NSInteger rawSection = KineticActivitySectionExplorer;
         rawSection <= KineticActivitySectionPlugins; ++rawSection) {
        KineticActivitySection section = (KineticActivitySection)rawSection;
        if (NSPointInRect(point, [self buttonRectForSection:section])) {
            return section;
        }
    }
    if (NSPointInRect(point, [self buttonRectForSection:KineticActivitySectionSettings])) {
        return KineticActivitySectionSettings;
    }
    return KineticActivitySectionNone;
}

- (NSString*)titleForSection:(KineticActivitySection)section {
    switch (section) {
    case KineticActivitySectionExplorer:
        return @"EXPLORER";
    case KineticActivitySectionSearch:
        return @"SEARCH";
    case KineticActivitySectionSourceControl:
        return @"SOURCE CONTROL / GITHUB";
    case KineticActivitySectionPlugins:
        return @"PLUGINS";
    case KineticActivitySectionSettings:
        return @"SETTINGS";
    case KineticActivitySectionNone:
        return @"";
    }
}

- (void)drawIconForSection:(KineticActivitySection)section inRect:(NSRect)rect {
    NSBezierPath* icon = [NSBezierPath bezierPath];
    icon.lineWidth = 1.2;
    icon.lineCapStyle = NSLineCapStyleRound;
    icon.lineJoinStyle = NSLineJoinStyleRound;
    CGFloat centerX = NSMidX(rect);
    CGFloat centerY = NSMidY(rect);

    switch (section) {
    case KineticActivitySectionExplorer: {
        [icon moveToPoint:NSMakePoint(centerX - 8.0, centerY - 5.5)];
        [icon lineToPoint:NSMakePoint(centerX - 3.0, centerY - 5.5)];
        [icon lineToPoint:NSMakePoint(centerX - 0.5, centerY - 3.0)];
        [icon lineToPoint:NSMakePoint(centerX + 8.0, centerY - 3.0)];
        [icon lineToPoint:NSMakePoint(centerX + 8.0, centerY + 6.0)];
        [icon lineToPoint:NSMakePoint(centerX - 8.0, centerY + 6.0)];
        [icon closePath];
        break;
    }
    case KineticActivitySectionSearch:
        [icon appendBezierPathWithOvalInRect:NSMakeRect(centerX - 6.5, centerY - 7.0, 12.0, 12.0)];
        [icon moveToPoint:NSMakePoint(centerX + 3.0, centerY + 3.0)];
        [icon lineToPoint:NSMakePoint(centerX + 7.5, centerY + 7.5)];
        break;
    case KineticActivitySectionSourceControl:
        [icon appendBezierPathWithOvalInRect:NSMakeRect(centerX - 7.0, centerY - 7.0, 4.0, 4.0)];
        [icon appendBezierPathWithOvalInRect:NSMakeRect(centerX + 3.0, centerY - 1.5, 4.0, 4.0)];
        [icon appendBezierPathWithOvalInRect:NSMakeRect(centerX - 7.0, centerY + 5.0, 4.0, 4.0)];
        [icon moveToPoint:NSMakePoint(centerX - 5.0, centerY - 3.0)];
        [icon lineToPoint:NSMakePoint(centerX - 5.0, centerY + 5.0)];
        [icon moveToPoint:NSMakePoint(centerX - 5.0, centerY - 1.0)];
        [icon curveToPoint:NSMakePoint(centerX + 3.0, centerY + 0.5)
             controlPoint1:NSMakePoint(centerX - 1.0, centerY - 1.0)
             controlPoint2:NSMakePoint(centerX - 1.0, centerY + 0.5)];
        break;
    case KineticActivitySectionPlugins: {
        [icon appendBezierPathWithRoundedRect:NSMakeRect(centerX - 6.0, centerY - 2.5, 12.0, 9.0)
                                      xRadius:2.5
                                      yRadius:2.5];
        [icon moveToPoint:NSMakePoint(centerX - 3.0, centerY - 2.5)];
        [icon lineToPoint:NSMakePoint(centerX - 3.0, centerY - 7.0)];
        [icon moveToPoint:NSMakePoint(centerX + 3.0, centerY - 2.5)];
        [icon lineToPoint:NSMakePoint(centerX + 3.0, centerY - 7.0)];
        [icon moveToPoint:NSMakePoint(centerX, centerY + 6.5)];
        [icon lineToPoint:NSMakePoint(centerX, centerY + 9.0)];
        break;
    }
    case KineticActivitySectionSettings:
        for (NSInteger index = 0; index < 3; ++index) {
            CGFloat y = centerY - 6.0 + index * 6.0;
            CGFloat knobX = centerX + (index == 1 ? 4.0 : -3.0);
            [icon moveToPoint:NSMakePoint(centerX - 8.0, y)];
            [icon lineToPoint:NSMakePoint(centerX + 8.0, y)];
            [icon appendBezierPathWithOvalInRect:NSMakeRect(knobX - 1.8, y - 1.8, 3.6, 3.6)];
        }
        break;
    case KineticActivitySectionNone:
        return;
    }

    if (section == _activeSection) {
        [activityColor(103, 158, 255) setStroke];
    } else if (section == _hoveredSection) {
        [activityColor(184, 196, 214) setStroke];
    } else {
        [activityColor(145, 159, 179) setStroke];
    }
    [icon stroke];
}

- (NSRect)panelButtonRectAtY:(CGFloat)y {
    return NSMakeRect(kRailWidth + 12.0, y, kPanelWidth - 24.0, 27.0);
}

- (NSRect)treeRowRectAtIndex:(NSUInteger)index {
    return NSMakeRect(kRailWidth + 7.0, kTreeStartY + index * kTreeRowHeight - _treeScrollOffset,
                      kPanelWidth - 14.0, kTreeRowHeight);
}

- (void)drawSectionHeader:(NSString*)title atY:(CGFloat)y attributes:(NSDictionary*)attributes {
    NSRect headerRect = NSMakeRect(kRailWidth + 1.0, y, kPanelWidth - 1.0, 24.0);
    [activityColor(48, 59, 74, 0.22) setFill];
    NSRectFill(headerRect);
    [activityColor(75, 89, 109, 0.24) setFill];
    NSRectFill(NSMakeRect(NSMinX(headerRect), NSMaxY(headerRect) - 1.0, NSWidth(headerRect), 1.0));

    [title drawInRect:NSMakeRect(kRailWidth + 14.0, y + 5.0, kPanelWidth - 28.0, 16.0)
        withAttributes:attributes];
}

- (void)drawPanelButtonInRect:(NSRect)rect title:(NSString*)title hovered:(BOOL)hovered {
    [activityColor(55, 67, 83, hovered ? 0.95 : 0.72) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:4.0 yRadius:4.0] fill];
    NSDictionary* attributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName : activityColor(218, 227, 239),
    };
    NSSize size = [title sizeWithAttributes:attributes];
    [title drawAtPoint:NSMakePoint(NSMidX(rect) - size.width * 0.5,
                                   NSMidY(rect) - size.height * 0.5)
        withAttributes:attributes];
}

- (void)drawTreeIconForEntry:(KineticActivityTreeEntry*)entry inRect:(NSRect)rect {
    NSBezierPath* icon = [NSBezierPath bezierPath];
    icon.lineWidth = 1.05;
    icon.lineCapStyle = NSLineCapStyleRound;
    icon.lineJoinStyle = NSLineJoinStyleRound;
    if (entry.directory) {
        [icon moveToPoint:NSMakePoint(NSMinX(rect), NSMinY(rect) + 4.0)];
        [icon lineToPoint:NSMakePoint(NSMinX(rect) + 5.0, NSMinY(rect) + 4.0)];
        [icon lineToPoint:NSMakePoint(NSMinX(rect) + 7.0, NSMinY(rect) + 2.0)];
        [icon lineToPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect) + 2.0)];
        [icon lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
        [icon lineToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
        [icon closePath];
        [activityColor(111, 166, 255) setStroke];
    } else {
        [icon appendBezierPathWithRoundedRect:NSInsetRect(rect, 2.0, 0.0) xRadius:1.2 yRadius:1.2];
        [activityColor(145, 159, 179) setStroke];
    }
    [icon stroke];
}

- (void)drawExplorerWithHeadingAttributes:(NSDictionary*)headingAttributes
                           bodyAttributes:(NSDictionary*)bodyAttributes
                          mutedAttributes:(NSDictionary*)mutedAttributes {
    [self drawSectionHeader:@"OPEN IN EDITOR" atY:45.0 attributes:headingAttributes];
    NSMutableParagraphStyle* truncatingStyle = [[NSMutableParagraphStyle alloc] init];
    truncatingStyle.lineBreakMode = NSLineBreakByTruncatingTail;
    NSMutableDictionary* documentAttributes = [bodyAttributes mutableCopy];
    documentAttributes[NSParagraphStyleAttributeName] = truncatingStyle;
    [activityColor(103, 158, 255, 0.68) setFill];
    NSRectFill(NSMakeRect(kRailWidth + 10.0, 78.0, 1.5, 15.0));
    [_documentTitle drawInRect:NSMakeRect(kRailWidth + 18.0, 77.0, kPanelWidth - 32.0, 18.0)
                withAttributes:documentAttributes];

    [self drawPanelButtonInRect:[self panelButtonRectAtY:110.0]
                          title:@"Open File…"
                        hovered:_hoveredPanelAction == 0];
    [self drawPanelButtonInRect:[self panelButtonRectAtY:143.0]
                          title:@"Open Folder…"
                        hovered:_hoveredPanelAction == 1];

    NSString* workspaceTitle = _workspaceUrl.lastPathComponent ?: @"NO FOLDER OPEN";
    [self drawSectionHeader:workspaceTitle.uppercaseString atY:181.0 attributes:headingAttributes];
    if (_workspaceUrl == nil) {
        [@"Open a folder to show its files."
                drawInRect:NSMakeRect(kRailWidth + 14.0, kTreeStartY + 7.0, kPanelWidth - 28.0,
                                      36.0)
            withAttributes:mutedAttributes];
        return;
    }

    NSRect treeClip = NSMakeRect(kRailWidth + 1.0, kTreeStartY, kPanelWidth - 1.0,
                                 MAX(0.0, NSHeight(self.bounds) - kTreeStartY));
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:treeClip] addClip];
    for (NSUInteger index = 0; index < _treeEntries.count; ++index) {
        NSRect rowRect = [self treeRowRectAtIndex:index];
        if (NSMinY(rowRect) > NSHeight(self.bounds)) {
            break;
        }
        if (NSMaxY(rowRect) < NSMinY(treeClip)) {
            continue;
        }
        if (_hoveredPanelAction == (NSInteger)index + 100) {
            [activityColor(77, 141, 255, 0.1) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:rowRect xRadius:3.0 yRadius:3.0] fill];
        }
        KineticActivityTreeEntry* entry = _treeEntries[index];
        CGFloat indentation = entry.depth * 13.0;
        NSRect iconRect =
            NSMakeRect(NSMinX(rowRect) + 7.0 + indentation, NSMidY(rowRect) - 5.5, 13.0, 11.0);
        [self drawTreeIconForEntry:entry inRect:iconRect];
        CGFloat textX = NSMaxX(iconRect) + 7.0;
        [entry.url.lastPathComponent drawInRect:NSMakeRect(textX, NSMinY(rowRect) + 4.0,
                                                           NSMaxX(rowRect) - textX - 6.0, 17.0)
                                 withAttributes:documentAttributes];
    }
    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawPanel {
    if (_displayedSection == KineticActivitySectionNone || NSWidth(self.bounds) <= kRailWidth) {
        return;
    }

    NSRect panelRect =
        NSMakeRect(kRailWidth, 0.0, NSWidth(self.bounds) - kRailWidth, NSHeight(self.bounds));
    [activityColor(42, 51, 64, 0.98) setFill];
    NSRectFill(panelRect);
    [activityColor(69, 82, 101, 0.38) setFill];
    NSRectFill(NSMakeRect(kRailWidth, 0.0, 1.0, NSHeight(self.bounds)));

    NSMutableParagraphStyle* truncatingStyle = [[NSMutableParagraphStyle alloc] init];
    truncatingStyle.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary* headingAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName : activityColor(151, 165, 184),
        NSParagraphStyleAttributeName : truncatingStyle,
    };
    NSDictionary* bodyAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : activityColor(215, 224, 237),
        NSParagraphStyleAttributeName : truncatingStyle,
    };
    NSDictionary* mutedAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : activityColor(132, 146, 166),
        NSParagraphStyleAttributeName : truncatingStyle,
    };

    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:NSInsetRect(panelRect, 1.0, 0.0)] addClip];
    [[self titleForSection:_displayedSection]
            drawInRect:NSMakeRect(kRailWidth + 14.0, 16.0, kPanelWidth - 28.0, 20.0)
        withAttributes:headingAttributes];
    [activityColor(75, 89, 109, 0.34) setFill];
    NSRectFill(NSMakeRect(kRailWidth + 1.0, 43.0, kPanelWidth - 1.0, 1.0));

    switch (_displayedSection) {
    case KineticActivitySectionExplorer:
        [self drawExplorerWithHeadingAttributes:headingAttributes
                                 bodyAttributes:bodyAttributes
                                mutedAttributes:mutedAttributes];
        break;
    case KineticActivitySectionSearch:
        [self drawSectionHeader:@"WORKSPACE SEARCH" atY:45.0 attributes:headingAttributes];
        [@"Search files and symbols"
                drawInRect:NSMakeRect(kRailWidth + 14.0, 82.0, kPanelWidth - 28.0, 18.0)
            withAttributes:bodyAttributes];
        [@"Workspace indexing is not active."
                drawInRect:NSMakeRect(kRailWidth + 14.0, 108.0, kPanelWidth - 28.0, 32.0)
            withAttributes:mutedAttributes];
        break;
    case KineticActivitySectionSourceControl:
        [self drawSectionHeader:@"REPOSITORY" atY:45.0 attributes:headingAttributes];
        [@"No repository detected"
                drawInRect:NSMakeRect(kRailWidth + 14.0, 82.0, kPanelWidth - 28.0, 18.0)
            withAttributes:bodyAttributes];
        [@"GitHub accounts and repositories will appear here."
                drawInRect:NSMakeRect(kRailWidth + 14.0, 108.0, kPanelWidth - 28.0, 34.0)
            withAttributes:mutedAttributes];
        break;
    case KineticActivitySectionPlugins:
        [self drawSectionHeader:@"INSTALLED" atY:45.0 attributes:headingAttributes];
        [@"Kinetic Core" drawInRect:NSMakeRect(kRailWidth + 14.0, 82.0, kPanelWidth - 28.0, 18.0)
                     withAttributes:bodyAttributes];
        [@"Third-party plugin loading is not active."
                drawInRect:NSMakeRect(kRailWidth + 14.0, 112.0, kPanelWidth - 28.0, 34.0)
            withAttributes:mutedAttributes];
        break;
    case KineticActivitySectionSettings:
    case KineticActivitySectionNone:
        break;
    }
    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [activityColor(44, 53, 66, 0.92) setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, kRailWidth, NSHeight(self.bounds)));
    [self drawPanel];

    for (NSInteger rawSection = KineticActivitySectionExplorer;
         rawSection <= KineticActivitySectionSettings; ++rawSection) {
        KineticActivitySection section = (KineticActivitySection)rawSection;
        NSRect buttonRect = [self buttonRectForSection:section];
        if (section == _activeSection) {
            [activityColor(77, 141, 255, 0.11) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:buttonRect xRadius:4.0 yRadius:4.0] fill];
            [activityColor(77, 141, 255) setFill];
            NSRectFill(NSMakeRect(0.0, NSMinY(buttonRect) + 7.0, 1.5, NSHeight(buttonRect) - 14.0));
        } else if (section == _hoveredSection) {
            [activityColor(124, 145, 174, 0.08) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:buttonRect xRadius:4.0 yRadius:4.0] fill];
        }
        [self drawIconForSection:section inRect:buttonRect];
    }
}

- (void)mouseDown:(NSEvent*)event {
    if (_animating) {
        return;
    }

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    KineticActivitySection section = [self sectionAtPoint:point];
    if (section != KineticActivitySectionNone) {
        if (section == _activeSection) {
            [self.delegate activityBar:self didActivateSection:KineticActivitySectionNone];
            [self deactivateSection];
            return;
        }

        _activeSection = section;
        [self.delegate activityBar:self didActivateSection:section];
        BOOL opensPanel = section != KineticActivitySectionSettings;
        if (opensPanel) {
            _displayedSection = section;
            if (NSWidth(self.frame) < kRailWidth + kPanelWidth - 0.5) {
                _animating = YES;
                NSRect targetFrame = self.frame;
                targetFrame.size.width = kRailWidth + kPanelWidth;
                [KineticTween animateView:self
                                  toFrame:targetFrame
                                  toAlpha:1.0
                                 duration:0.15
                               completion:^{
                                 self->_animating = NO;
                                 self.needsDisplay = YES;
                               }];
            }
        } else if (NSWidth(self.frame) > kRailWidth + 0.5) {
            _animating = YES;
            NSRect targetFrame = self.frame;
            targetFrame.size.width = kRailWidth;
            [KineticTween animateView:self
                              toFrame:targetFrame
                              toAlpha:1.0
                             duration:0.15
                           completion:^{
                             self->_displayedSection = KineticActivitySectionNone;
                             self->_animating = NO;
                             self.needsDisplay = YES;
                           }];
        } else {
            _displayedSection = KineticActivitySectionNone;
        }
        self.needsDisplay = YES;
        return;
    }

    if (_activeSection == KineticActivitySectionExplorer) {
        if (NSPointInRect(point, [self panelButtonRectAtY:110.0])) {
            [self.delegate activityBarDidRequestOpenFile:self];
            return;
        }
        if (NSPointInRect(point, [self panelButtonRectAtY:143.0])) {
            [self.delegate activityBarDidRequestOpenFolder:self];
            return;
        }
        for (NSUInteger index = 0; point.y >= kTreeStartY && index < _treeEntries.count; ++index) {
            if (!NSPointInRect(point, [self treeRowRectAtIndex:index])) {
                continue;
            }
            KineticActivityTreeEntry* entry = _treeEntries[index];
            if (entry.directory) {
                if ([_expandedPaths containsObject:entry.url.path]) {
                    [_expandedPaths removeObject:entry.url.path];
                } else {
                    [_expandedPaths addObject:entry.url.path];
                }
                [self reloadTreeEntries];
            } else {
                [self.delegate activityBar:self didRequestOpenUrl:entry.url];
            }
            return;
        }
    }
}

- (void)resetCursorRects {
    [super resetCursorRects];
    [self addCursorRect:self.bounds cursor:NSCursor.arrowCursor];
}

- (void)scrollWheel:(NSEvent*)event {
    if (_activeSection != KineticActivitySectionExplorer || _workspaceUrl == nil) {
        return;
    }
    _treeScrollOffset =
        MIN([self maximumTreeScroll], MAX(0.0, _treeScrollOffset - event.scrollingDeltaY));
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
    KineticActivitySection hovered = [self sectionAtPoint:point];
    NSInteger panelAction = -1;
    if (_activeSection == KineticActivitySectionExplorer) {
        if (NSPointInRect(point, [self panelButtonRectAtY:110.0])) {
            panelAction = 0;
        } else if (NSPointInRect(point, [self panelButtonRectAtY:143.0])) {
            panelAction = 1;
        } else {
            for (NSUInteger index = 0; point.y >= kTreeStartY && index < _treeEntries.count;
                 ++index) {
                if (NSPointInRect(point, [self treeRowRectAtIndex:index])) {
                    panelAction = (NSInteger)index + 100;
                    break;
                }
            }
        }
    }
    if (hovered != _hoveredSection) {
        _hoveredSection = hovered;
        self.needsDisplay = YES;
    }
    if (panelAction != _hoveredPanelAction) {
        _hoveredPanelAction = panelAction;
        self.needsDisplay = YES;
    }
}

- (void)mouseExited:(NSEvent*)event {
    (void)event;
    _hoveredSection = KineticActivitySectionNone;
    _hoveredPanelAction = -1;
    self.needsDisplay = YES;
}

@end
