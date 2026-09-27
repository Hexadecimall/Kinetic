#import "pluginBrowser.h"
#import "contextMenu.h"

namespace {
constexpr CGFloat kListWidth = 340.0;
constexpr CGFloat kCardHeight = 106.0;
constexpr CGFloat kCardGap = 9.0;

NSColor* browserColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha = 1.0) {
    return [NSColor colorWithSRGBRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:alpha];
}

NSDictionary* browserText(CGFloat size, NSFontWeight weight, NSColor* color) {
    NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    return @{
        NSFontAttributeName : [NSFont systemFontOfSize:size weight:weight],
        NSForegroundColorAttributeName : color,
        NSParagraphStyleAttributeName : paragraph,
    };
}
} // namespace

@interface KineticPluginBrowser () <NSTextFieldDelegate> {
    NSTextField* _searchField;
    BOOL _installedOnly;
    CGFloat _listScroll;
    NSString* _selectedId;
    NSInteger _hoveredCard;
}
@end

@implementation KineticPluginBrowser

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _plugins = @[];
        _status = @"Loading the public catalog…";
        _hoveredCard = -1;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _searchField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _searchField.placeholderString = @"Search plugins or publishers";
        _searchField.font = [NSFont systemFontOfSize:14.0];
        _searchField.textColor = browserColor(226, 233, 242);
        _searchField.backgroundColor = NSColor.clearColor;
        _searchField.drawsBackground = NO;
        _searchField.bordered = NO;
        _searchField.focusRingType = NSFocusRingTypeNone;
        _searchField.delegate = self;
        [self addSubview:_searchField];
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)layout {
    [super layout];
    _searchField.frame = NSMakeRect(47.0, 92.0, MIN(420.0, NSWidth(self.bounds) - 94.0), 24.0);
}

- (void)setPlugins:(NSArray<NSDictionary<NSString*, id>*>*)plugins {
    _plugins = [plugins copy] ?: @[];
    if (_selectedId.length == 0 && _plugins.count > 0) {
        _selectedId = [_plugins.firstObject[@"id"] copy];
    }
    _listScroll = 0.0;
    self.needsDisplay = YES;
}

- (void)setStatus:(NSString*)status {
    _status = [status copy];
    self.needsDisplay = YES;
}

- (NSArray<NSDictionary<NSString*, id>*>*)filteredPlugins {
    NSString* query = _searchField.stringValue.lowercaseString;
    NSMutableArray* result = [NSMutableArray array];
    for (NSDictionary<NSString*, id>* plugin in _plugins) {
        NSString* state = plugin[@"state"] ?: @"available";
        if (_installedOnly && [state isEqualToString:@"available"]) {
            continue;
        }
        if (query.length > 0 &&
            ![[(plugin[@"name"] ?: @"") lowercaseString] containsString:query] &&
            ![[(plugin[@"publisher"] ?: @"") lowercaseString] containsString:query] &&
            ![[(plugin[@"summary"] ?: @"") lowercaseString] containsString:query]) {
            continue;
        }
        [result addObject:plugin];
    }
    return result;
}

- (NSDictionary<NSString*, id>*)selectedPlugin {
    NSArray* filtered = [self filteredPlugins];
    for (NSDictionary* plugin in filtered) {
        if ([plugin[@"id"] isEqualToString:_selectedId]) {
            return plugin;
        }
    }
    return filtered.firstObject;
}

- (NSRect)cardRectAtIndex:(NSUInteger)index {
    return NSMakeRect(24.0, 171.0 + index * (kCardHeight + kCardGap) - _listScroll,
                      MIN(kListWidth, MAX(200.0, NSWidth(self.bounds) * 0.44)), kCardHeight);
}

- (CGFloat)detailX {
    return NSMaxX([self cardRectAtIndex:0]) + 27.0;
}

- (NSRect)primaryActionRect {
    return NSMakeRect([self detailX] + 23.0, 371.0, 120.0, 34.0);
}

- (NSRect)secondaryActionRect {
    return NSMakeRect([self detailX] + 153.0, 371.0, 120.0, 34.0);
}

- (void)drawIconForPlugin:(NSDictionary*)plugin inRect:(NSRect)rect {
    BOOL official = [plugin[@"official"] boolValue];
    [browserColor(official ? 60 : 67, official ? 93 : 78, official ? 145 : 100) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:9.0 yRadius:9.0] fill];
    NSString* name = plugin[@"name"] ?: @"Plugin";
    NSString* mark = [plugin[@"id"] isEqualToString:@"kinetic.cpp-support"]
                         ? @"C++"
                         : [name substringToIndex:MIN((NSUInteger)2, name.length)].uppercaseString;
    NSDictionary* attributes = browserText(rect.size.width > 50.0 ? 23.0 : 17.0,
                                           NSFontWeightSemibold, browserColor(234, 241, 252));
    NSSize size = [mark sizeWithAttributes:attributes];
    [mark drawAtPoint:NSMakePoint(NSMidX(rect) - size.width * 0.5, NSMidY(rect) - size.height * 0.5)
        withAttributes:attributes];
}

- (void)drawAction:(NSString*)title inRect:(NSRect)rect enabled:(BOOL)enabled {
    [browserColor(enabled ? 74 : 62, enabled ? 129 : 73, enabled ? 222 : 88, enabled ? 0.95 : 0.55)
        setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:5.0 yRadius:5.0] fill];
    NSDictionary* attributes =
        browserText(13.0, NSFontWeightMedium,
                    enabled ? browserColor(239, 245, 254) : browserColor(145, 157, 175));
    NSSize size = [title sizeWithAttributes:attributes];
    [title drawAtPoint:NSMakePoint(NSMidX(rect) - size.width * 0.5,
                                   NSMidY(rect) - size.height * 0.5)
        withAttributes:attributes];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [browserColor(44, 54, 68, 0.97) setFill];
    NSRectFill(self.bounds);
    NSDictionary* title = browserText(25.0, NSFontWeightSemibold, browserColor(235, 241, 249));
    NSDictionary* body = browserText(14.0, NSFontWeightMedium, browserColor(222, 230, 242));
    NSDictionary* muted = browserText(12.0, NSFontWeightRegular, browserColor(144, 160, 180));
    NSDictionary* small = browserText(11.0, NSFontWeightMedium, browserColor(139, 179, 250));

    [@"Plugins" drawAtPoint:NSMakePoint(25.0, 27.0) withAttributes:title];
    [@"Find and manage extensions for this editor." drawAtPoint:NSMakePoint(26.0, 61.0)
                                                 withAttributes:muted];
    if (_status.length > 0) {
        [_status drawInRect:NSMakeRect(NSWidth(self.bounds) - 305.0, 45.0, 280.0, 22.0)
             withAttributes:muted];
    }
    NSRect search = NSMakeRect(25.0, 83.0, MIN(460.0, NSWidth(self.bounds) - 50.0), 42.0);
    [browserColor(34, 43, 57) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:search xRadius:6.0 yRadius:6.0] fill];
    [browserColor(81, 101, 132, 0.6) setStroke];
    [[NSBezierPath bezierPathWithRoundedRect:search xRadius:6.0 yRadius:6.0] stroke];
    NSBezierPath* searchIcon =
        [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(36.0, 97.0, 10.0, 10.0)];
    searchIcon.lineWidth = 1.4;
    [searchIcon moveToPoint:NSMakePoint(44.5, 105.5)];
    [searchIcon lineToPoint:NSMakePoint(50.0, 111.0)];
    [browserColor(153, 174, 202) setStroke];
    [searchIcon stroke];
    [@"Discover" drawAtPoint:NSMakePoint(26.0, 145.0)
              withAttributes:_installedOnly ? muted : small];
    [@"Installed" drawAtPoint:NSMakePoint(111.0, 145.0)
               withAttributes:_installedOnly ? small : muted];
    [@"Refresh" drawAtPoint:NSMakePoint(NSWidth(self.bounds) - 75.0, 145.0) withAttributes:muted];
    [browserColor(76, 91, 112, 0.43) setFill];
    NSRectFill(NSMakeRect(24.0, 168.0, NSWidth(self.bounds) - 48.0, 1.0));

    NSArray<NSDictionary<NSString*, id>*>* filtered = [self filteredPlugins];
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:NSMakeRect(18.0, 170.0, [self detailX] - 27.0,
                                                 MAX(0.0, NSHeight(self.bounds) - 170.0))] addClip];
    for (NSUInteger index = 0; index < filtered.count; ++index) {
        NSDictionary* plugin = filtered[index];
        NSRect card = [self cardRectAtIndex:index];
        BOOL selected = [plugin[@"id"] isEqualToString:[self selectedPlugin][@"id"]];
        [browserColor(selected ? 55 : 49, selected ? 70 : 61, selected ? 92 : 78) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:card xRadius:7.0 yRadius:7.0] fill];
        if (selected) {
            [browserColor(91, 151, 255) setFill];
            NSRectFill(NSMakeRect(NSMinX(card), NSMinY(card) + 7.0, 2.0, NSHeight(card) - 14.0));
        }
        [self drawIconForPlugin:plugin
                         inRect:NSMakeRect(NSMinX(card) + 12.0, NSMinY(card) + 13.0, 43.0, 43.0)];
        CGFloat textX = NSMinX(card) + 66.0;
        [plugin[@"name"]
                drawInRect:NSMakeRect(textX, NSMinY(card) + 12.0, NSWidth(card) - 80.0, 19.0)
            withAttributes:body];
        NSString* publisher = plugin[@"publisher"] ?: @"Unknown publisher";
        [publisher drawInRect:NSMakeRect(textX, NSMinY(card) + 33.0, NSWidth(card) - 80.0, 17.0)
               withAttributes:muted];
        [plugin[@"summary"] drawInRect:NSMakeRect(NSMinX(card) + 12.0, NSMinY(card) + 69.0,
                                                  NSWidth(card) - 24.0, 28.0)
                        withAttributes:muted];
    }
    [NSGraphicsContext restoreGraphicsState];

    if (filtered.count == 0) {
        NSString* emptyMessage = _searchField.stringValue.length > 0
                                     ? @"No plugins match this search."
                                 : _installedOnly ? @"No plugins installed."
                                                  : (_status ?: @"No plugins available.");
        [emptyMessage drawInRect:NSMakeRect(28.0, 191.0, [self detailX] - 65.0, 70.0)
                  withAttributes:muted];
    }
    NSDictionary* selected = [self selectedPlugin];
    if (selected == nil) {
        return;
    }
    CGFloat x = [self detailX] + 23.0;
    CGFloat width = MAX(190.0, NSWidth(self.bounds) - x - 28.0);
    [self drawIconForPlugin:selected inRect:NSMakeRect(x, 193.0, 66.0, 66.0)];
    [selected[@"name"]
            drawInRect:NSMakeRect(x + 78.0, 194.0, width - 78.0, 30.0)
        withAttributes:browserText(21.0, NSFontWeightSemibold, browserColor(233, 240, 250))];
    NSString* publisher =
        [NSString stringWithFormat:@"by %@  ·  %@", selected[@"publisher"] ?: @"Unknown",
                                   [selected[@"official"] boolValue] ? @"Official" : @"Community"];
    [publisher drawInRect:NSMakeRect(x + 78.0, 229.0, width - 78.0, 19.0) withAttributes:muted];
    [@"ABOUT" drawAtPoint:NSMakePoint(x, 279.0) withAttributes:small];
    NSMutableParagraphStyle* summaryStyle = [[NSMutableParagraphStyle alloc] init];
    summaryStyle.lineBreakMode = NSLineBreakByWordWrapping;
    NSMutableDictionary* summaryAttributes = [body mutableCopy];
    summaryAttributes[NSParagraphStyleAttributeName] = summaryStyle;
    [selected[@"summary"] drawInRect:NSMakeRect(x, 302.0, width, 68.0)
                      withAttributes:summaryAttributes];
    NSString* state = selected[@"state"] ?: @"available";
    NSString* action = [state hasPrefix:@"update available"] ? @"Update"
                       : [state hasPrefix:@"installed"]      ? @"Installed"
                                                             : @"Install";
    [self drawAction:action
              inRect:[self primaryActionRect]
             enabled:![action isEqualToString:@"Installed"]];
    if (![state isEqualToString:@"available"]) {
        [self drawAction:@"Remove" inRect:[self secondaryActionRect] enabled:YES];
    }
    [@"VERSION" drawAtPoint:NSMakePoint(x, 436.0) withAttributes:small];
    [selected[@"version"] drawAtPoint:NSMakePoint(x, 454.0) withAttributes:body];
    [@"PUBLISHER" drawAtPoint:NSMakePoint(x, 496.0) withAttributes:small];
    [publisher drawInRect:NSMakeRect(x, 514.0, width, 20.0) withAttributes:body];
    [@"RATING" drawAtPoint:NSMakePoint(x, 556.0) withAttributes:small];
    [@"☆☆☆☆☆  No ratings yet" drawAtPoint:NSMakePoint(x, 574.0) withAttributes:muted];
    NSString* technical = [NSString stringWithFormat:@"%@  ·  API %@  ·  %.0f KiB",
                                                     selected[@"platform"] ?: @"macos-arm64",
                                                     selected[@"apiVersion"] ?: @1,
                                                     [selected[@"sizeBytes"] doubleValue] / 1024.0];
    [technical drawInRect:NSMakeRect(x, 620.0, width, 19.0) withAttributes:muted];
    [selected[@"id"] drawInRect:NSMakeRect(x, 640.0, width, 19.0) withAttributes:muted];
    [@"Native plugins run with Kinetic's permissions. Restart after changes."
            drawInRect:NSMakeRect(x, 664.0, width, 34.0)
        withAttributes:muted];
}

- (void)controlTextDidChange:(NSNotification*)notification {
    (void)notification;
    _listScroll = 0.0;
    self.needsDisplay = YES;
}

- (void)showConfirmationForPlugin:(NSDictionary*)plugin
                           action:(NSString*)action
                          atPoint:(NSPoint)point {
    NSString* publisher = plugin[@"publisher"] ?: @"Unknown";
    NSString* trust = [plugin[@"official"] boolValue] ? @"Official" : @"Community";
    NSArray* items = @[
        @{@"title" : [NSString stringWithFormat:@"Publisher: %@", publisher], @"enabled" : @NO},
        @{@"title" : [NSString stringWithFormat:@"%@ native plugin", trust], @"enabled" : @NO},
        @{
            @"title" : [action isEqualToString:@"uninstall"] ? @"Remove plugin"
                                                             : @"Runs with file access",
            @"enabled" : @NO
        },
        @{@"title" : [action.capitalizedString stringByAppendingString:@" plugin"]},
        @{@"title" : @"Cancel"},
    ];
    [KineticContextMenu showInView:self
                           atPoint:point
                             items:items
                           handler:^(NSUInteger index) {
                             if (index == 3) {
                                 [self.delegate pluginBrowser:self
                                             didRequestAction:action
                                                    forPlugin:plugin];
                             }
                           }];
}

- (void)mouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (point.y >= 135.0 && point.y < 169.0) {
        if (point.x < 99.0) {
            _installedOnly = NO;
            _listScroll = 0.0;
        } else if (point.x < 194.0) {
            _installedOnly = YES;
            _listScroll = 0.0;
        } else if (point.x > NSWidth(self.bounds) - 94.0) {
            [self.delegate pluginBrowserDidRequestRefresh:self];
        }
        self.needsDisplay = YES;
        return;
    }
    NSArray* filtered = [self filteredPlugins];
    for (NSUInteger index = 0; index < filtered.count; ++index) {
        if (NSPointInRect(point, [self cardRectAtIndex:index]) && point.y >= 170.0) {
            _selectedId = [filtered[index][@"id"] copy];
            self.needsDisplay = YES;
            return;
        }
    }
    NSDictionary* selected = [self selectedPlugin];
    NSString* state = selected[@"state"] ?: @"available";
    if (selected != nil && NSPointInRect(point, [self primaryActionRect])) {
        NSString* action = [state hasPrefix:@"update available"] ? @"update" : @"install";
        if (![state hasPrefix:@"installed"]) {
            [self showConfirmationForPlugin:selected action:action atPoint:point];
        } else if ([action isEqualToString:@"update"]) {
            [self showConfirmationForPlugin:selected action:action atPoint:point];
        }
        return;
    }
    if (selected != nil && NSPointInRect(point, [self secondaryActionRect]) &&
        ![state isEqualToString:@"available"]) {
        [self showConfirmationForPlugin:selected action:@"uninstall" atPoint:point];
    }
}

- (void)scrollWheel:(NSEvent*)event {
    NSArray* filtered = [self filteredPlugins];
    CGFloat contentHeight = filtered.count * (kCardHeight + kCardGap);
    CGFloat viewport = MAX(100.0, NSHeight(self.bounds) - 181.0);
    _listScroll =
        MIN(MAX(0.0, contentHeight - viewport), MAX(0.0, _listScroll - event.scrollingDeltaY));
    self.needsDisplay = YES;
}

@end
