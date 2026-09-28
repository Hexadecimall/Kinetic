#import "settingsPanel.h"
#import "contextMenu.h"
#import "theme.h"

namespace {
NSDictionary* row(NSString* group, NSString* title, NSString* key, double minimum = 0,
                  double maximum = 1, double step = 1, NSArray* choices = nil) {
    return @{
        @"group" : group,
        @"title" : title,
        @"key" : key,
        @"min" : @(minimum),
        @"max" : @(maximum),
        @"step" : @(step),
        @"choices" : choices ?: @[]
    };
}
NSColor* color(CGFloat r, CGFloat g, CGFloat b, CGFloat a = 1) {
    return kineticThemeColor(r, g, b, a);
}
NSDictionary* textStyle(CGFloat size, NSColor* foreground) {
    NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    return @{
        NSFontAttributeName : [NSFont systemFontOfSize:size],
        NSForegroundColorAttributeName : foreground,
        NSParagraphStyleAttributeName : paragraph
    };
}
void centered(NSString* text, NSRect rect, NSDictionary* style) {
    NSSize size = [text sizeWithAttributes:style];
    [text drawAtPoint:NSMakePoint(NSMidX(rect) - size.width / 2, NSMidY(rect) - size.height / 2)
        withAttributes:style];
}
NSArray* groups() {
    return @[
        @"Appearance", @"Indentation", @"Completion", @"Navigation", @"Interface", @"Application"
    ];
}
} // namespace

NSArray<NSDictionary*>* kineticSettingsRows(void) {
    return @[
        row(@"Appearance", @"Theme", @"interface.theme", 0, 2, 1,
            @[ @"Kinetic Dark", @"Midnight", @"Graphite" ]),
        row(@"Appearance", @"Font", @"editor.text.fontPreset", 0, 3, 1,
            @[ @"System Mono", @"Menlo", @"Monaco", @"Courier" ]),
        row(@"Appearance", @"Font size", @"editor.text.fontSize", 8, 28),
        row(@"Appearance", @"Line height", @"editor.text.lineHeight", 14, 40),
        row(@"Appearance", @"Letter spacing", @"editor.text.letterSpacing", -2, 8, 0.25),
        row(@"Appearance", @"Line numbers", @"editor.gutter.lineNumbers"),
        row(@"Appearance", @"Syntax highlighting", @"editor.syntax.enabled"),
        row(@"Appearance", @"Highlight current line", @"editor.currentLine.enabled"),
        row(@"Appearance", @"Diagnostics", @"editor.diagnostics.enabled"),
        row(@"Indentation", @"Tab width", @"editor.indentation.tabWidth", 1, 16),
        row(@"Indentation", @"Use tab characters", @"editor.indentation.insertTabs"),
        row(@"Indentation", @"Automatic indentation", @"editor.indentation.autoIndent"),
        row(@"Indentation", @"Move by indentation unit", @"editor.indentation.unitNavigation"),
        row(@"Indentation", @"Indent guides", @"editor.indentation.guides"),
        row(@"Indentation", @"Pair brackets and quotes", @"editor.delimiters.autoPairs"),
        row(@"Completion", @"Autocomplete", @"editor.autocomplete.enabled"),
        row(@"Completion", @"Minimum prefix", @"editor.autocomplete.minPrefix", 1, 8),
        row(@"Completion", @"Suggestion limit", @"editor.autocomplete.maxResults", 1, 32),
        row(@"Navigation", @"Natural scrolling", @"editor.scroll.natural"),
        row(@"Navigation", @"Scroll indicators", @"editor.scroll.indicators"),
        row(@"Interface", @"Panel and switch animations", @"interface.motion.enabled"),
        row(@"Interface", @"Animation duration (ms)", @"interface.motion.duration", 80, 400, 20),
        row(@"Interface", @"Preferred tab width", @"editor.tabs.preferredWidth", 100, 240, 4)
    ];
}

@interface KineticSettingsPanel () <NSTextFieldDelegate> {
    NSTextField* _search;
    NSInteger _category;
    CGFloat _scroll;
    NSMutableDictionary<NSString*, NSDictionary*>* _switches;
    NSTimer* _timer;
    NSString* _error;
    NSInteger _focusedRow;
}
@end

@implementation KineticSettingsPanel
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _switches = [NSMutableDictionary dictionary];
        _focusedRow = -1;
        _search = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _search.placeholderString = @"Search settings";
        _search.font = [NSFont systemFontOfSize:13];
        _search.textColor = color(226, 233, 242);
        _search.drawsBackground = NO;
        _search.bordered = NO;
        _search.focusRingType = NSFocusRingTypeNone;
        _search.delegate = self;
        [self addSubview:_search];
    }
    return self;
}
- (BOOL)isFlipped {
    return YES;
}
- (BOOL)acceptsFirstResponder {
    return YES;
}
- (void)layout {
    [super layout];
    _search.frame = NSMakeRect(196, 26, MAX(40, NSWidth(self.bounds) - 264), 22);
}
- (NSArray<NSDictionary*>*)visibleRows {
    NSString* query =
        [_search.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSMutableArray* result = [NSMutableArray array];
    for (NSDictionary* item in kineticSettingsRows()) {
        if (query.length > 0) {
            if ([item[@"title"] localizedCaseInsensitiveContainsString:query] ||
                [item[@"key"] localizedCaseInsensitiveContainsString:query] ||
                [item[@"group"] localizedCaseInsensitiveContainsString:query])
                [result addObject:item];
        } else if ([item[@"group"] isEqual:groups()[_category]])
            [result addObject:item];
    }
    return result;
}
- (NSRect)listRect {
    return NSMakeRect(184, 110, MAX(1, NSWidth(self.bounds) - 208),
                      MAX(1, NSHeight(self.bounds) - 140));
}
- (NSRect)rowRect:(NSInteger)index {
    NSRect list = [self listRect];
    return NSMakeRect(NSMinX(list), NSMinY(list) + index * 48 - _scroll, NSWidth(list), 46);
}
- (NSRect)controlRect:(NSInteger)index {
    NSRect rect = [self rowRect:index];
    return NSMakeRect(NSMaxX(rect) - 126, NSMinY(rect) + 8, 120, 30);
}
- (CGFloat)switchProgress:(NSString*)key value:(double)value {
    NSDictionary* animation = _switches[key];
    if (!animation)
        return value;
    double t = MIN(1, (NSProcessInfo.processInfo.systemUptime - [animation[@"start"] doubleValue]) /
                          [animation[@"duration"] doubleValue]);
    return
        [animation[@"from"] doubleValue] +
        ([animation[@"to"] doubleValue] - [animation[@"from"] doubleValue]) * (1 - pow(1 - t, 3));
}
- (void)step:(NSTimer*)timer {
    for (NSString* key in _switches.allKeys) {
        NSDictionary* animation = _switches[key];
        if (NSProcessInfo.processInfo.systemUptime - [animation[@"start"] doubleValue] >=
            [animation[@"duration"] doubleValue])
            [_switches removeObjectForKey:key];
    }
    self.needsDisplay = YES;
    if (_switches.count == 0) {
        [timer invalidate];
        _timer = nil;
    }
}
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    [color(44, 54, 68) setFill];
    NSRectFill(self.bounds);
    [@"Settings" drawAtPoint:NSMakePoint(24, 24)
              withAttributes:textStyle(22, color(235, 240, 247))];
    [color(35, 44, 58) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(184, 18, NSWidth(self.bounds) - 246, 38)
                                     xRadius:6
                                     yRadius:6] fill];
    NSDictionary* text = textStyle(13, color(220, 229, 241));
    for (NSInteger index = 0; index < (NSInteger)groups().count; ++index) {
        NSRect rect = NSMakeRect(12, 84 + index * 38, 154, 32);
        if (_search.stringValue.length == 0 && index == _category) {
            [color(61, 83, 120, 0.6) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:5 yRadius:5] fill];
        }
        [groups()[index] drawAtPoint:NSMakePoint(24, NSMinY(rect) + 8) withAttributes:text];
    }
    NSString* heading = _search.stringValue.length ? @"Search results" : groups()[_category];
    [heading drawAtPoint:NSMakePoint(190, 82) withAttributes:textStyle(14, color(180, 194, 214))];
    NSRect list = [self listRect];
    NSArray* rows = [self visibleRows];
    _scroll = MIN(_scroll, MAX(0, rows.count * 48.0 - NSHeight(list)));
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:list] addClip];
    for (NSInteger index = 0; index < (NSInteger)rows.count; ++index) {
        NSDictionary* item = rows[index];
        NSRect rect = [self rowRect:index];
        if (!NSIntersectsRect(rect, list))
            continue;
        if (index == _focusedRow && self.window.firstResponder == self) {
            [color(61, 83, 120, 0.3) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:5 yRadius:5] fill];
        }
        [item[@"title"]
                drawInRect:NSMakeRect(NSMinX(rect) + 6, NSMinY(rect) + 14, NSWidth(rect) - 148, 20)
            withAttributes:text];
        double value = self.readNumber ? self.readNumber(item[@"key"]) : 0;
        NSRect control = [self controlRect:index];
        NSArray* choices = item[@"choices"];
        BOOL toggle = [item[@"min"] doubleValue] == 0 && [item[@"max"] doubleValue] == 1 &&
                      choices.count == 0;
        if (toggle) {
            NSRect track = NSMakeRect(NSMaxX(control) - 38, NSMidY(control) - 11, 38, 22);
            CGFloat progress = [self switchProgress:item[@"key"] value:value];
            NSColor* fill = [color(74, 87, 105) blendedColorWithFraction:progress
                                                                 ofColor:color(77, 141, 255)];
            [fill setFill];
            [[NSBezierPath bezierPathWithRoundedRect:track xRadius:11 yRadius:11] fill];
            [color(235, 240, 247) setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMinX(track) + 3 + progress * 16,
                                                               NSMinY(track) + 3, 16, 16)] fill];
        } else {
            [color(35, 44, 58) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:control xRadius:5 yRadius:5] fill];
            if (choices.count) {
                centered(choices[MIN(choices.count - 1, (NSUInteger)MAX(0, value))], control, text);
            } else {
                centered(@"−", NSMakeRect(NSMinX(control), NSMinY(control), 30, 30), text);
                centered(@"+", NSMakeRect(NSMaxX(control) - 30, NSMinY(control), 30, 30), text);
                centered([NSString stringWithFormat:@"%g", value],
                         NSMakeRect(NSMinX(control) + 30, NSMinY(control), 60, 30), text);
            }
        }
    }
    if (rows.count == 0 && (_category != 5 || _search.stringValue.length)) {
        [@"No matching settings" drawAtPoint:NSMakePoint(190, 130) withAttributes:text];
    }
    if (_category == 5 && _search.stringValue.length == 0) {
        NSArray* actions =
            @[ @"Check for updates", @"Install / update Kinetic", @"Uninstall Kinetic…" ];
        for (NSInteger index = 0; index < 3; ++index) {
            NSRect rect = [self rowRect:index];
            [color(50, 61, 76) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:5 yRadius:5] fill];
            [actions[index] drawAtPoint:NSMakePoint(NSMinX(rect) + 12, NSMinY(rect) + 14)
                         withAttributes:text];
        }
        [(self.applicationStatus ?: @"") drawInRect:NSMakeRect(190, 270, NSWidth(list) - 12, 90)
                                     withAttributes:textStyle(12, color(139, 155, 177))];
    }
    [NSGraphicsContext restoreGraphicsState];
    if (_error.length)
        [_error drawInRect:NSMakeRect(190, NSHeight(self.bounds) - 27, NSWidth(list), 20)
            withAttributes:textStyle(12, color(235, 139, 139))];
    CGFloat contentHeight = rows.count * 48.0;
    if (contentHeight > NSHeight(list)) {
        CGFloat height = MAX(24, NSHeight(list) * NSHeight(list) / contentHeight);
        CGFloat y =
            NSMinY(list) + _scroll / (contentHeight - NSHeight(list)) * (NSHeight(list) - height);
        [color(139, 155, 177, 0.45) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSWidth(self.bounds) - 11, y, 3, height)
                                         xRadius:1.5
                                         yRadius:1.5] fill];
    }
}
- (void)changeRow:(NSInteger)index direction:(NSInteger)direction {
    NSArray* rows = [self visibleRows];
    if (index < 0 || index >= (NSInteger)rows.count || !self.writeNumber || !self.readNumber)
        return;
    NSDictionary* item = rows[index];
    NSString* key = item[@"key"];
    double current = self.readNumber(key);
    double minimum = [item[@"min"] doubleValue], maximum = [item[@"max"] doubleValue];
    BOOL toggle = minimum == 0 && maximum == 1 && [item[@"choices"] count] == 0;
    double value =
        toggle ? !current
               : MIN(maximum, MAX(minimum, current + direction * [item[@"step"] doubleValue]));
    if ([item[@"choices"] count])
        value = current + direction > maximum   ? minimum
                : current + direction < minimum ? maximum
                                                : current + direction;
    CGFloat from = [self switchProgress:key value:current];
    BOOL animated = self.readNumber(@"interface.motion.enabled") != 0;
    double duration = self.readNumber(@"interface.motion.duration") / 1000;
    _error = self.writeNumber(key, value) ? nil : @"Could not save this setting.";
    if (toggle && animated && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        _switches[key] = @{
            @"from" : @(from),
            @"to" : @(value),
            @"start" : @(NSProcessInfo.processInfo.systemUptime),
            @"duration" : @(MAX(0.08, duration))
        };
        if (!_timer)
            _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                      target:self
                                                    selector:@selector(step:)
                                                    userInfo:nil
                                                     repeats:YES];
    }
    self.needsDisplay = YES;
}
- (void)mouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    [self.window makeFirstResponder:self];
    for (NSInteger index = 0; index < (NSInteger)groups().count; ++index) {
        if (NSPointInRect(point, NSMakeRect(12, 84 + index * 38, 154, 32))) {
            _category = index;
            _scroll = 0;
            _focusedRow = -1;
            _search.stringValue = @"";
            self.needsDisplay = YES;
            return;
        }
    }
    if (!NSPointInRect(point, [self listRect]))
        return;
    if (_category == 5 && _search.stringValue.length == 0) {
        for (NSInteger index = 0; index < 3; ++index) {
            if (!NSPointInRect(point, [self rowRect:index]))
                continue;
            NSString* action = @[ @"check", @"update", @"uninstall" ][index];
            if (index == 0) {
                if (self.applicationAction)
                    self.applicationAction(action);
            } else
                [KineticContextMenu showInView:self
                                       atPoint:point
                                         items:@[
                                             @{
                                                 @"title" : index == 1 ? @"Confirm install / update"
                                                                       : @"Move Kinetic to Trash"
                                             },
                                             @{@"title" : @"Cancel"}
                                         ]
                                       handler:^(NSUInteger selected) {
                                         if (selected == 0 && self.applicationAction)
                                             self.applicationAction(action);
                                       }];
        }
        return;
    }
    for (NSInteger index = 0; index < (NSInteger)[self visibleRows].count; ++index) {
        NSRect control = [self controlRect:index];
        if (!NSPointInRect(point, control))
            continue;
        _focusedRow = index;
        NSDictionary* item = [self visibleRows][index];
        NSArray* choices = item[@"choices"];
        if (choices.count > 0) {
            NSMutableArray* items = [NSMutableArray array];
            for (NSString* choice in choices)
                [items addObject:@{@"title" : choice}];
            [KineticContextMenu showInView:self
                                   atPoint:NSMakePoint(NSMinX(control), NSMaxY(control) + 3)
                                     items:items
                                   handler:^(NSUInteger selected) {
                                     if (selected < choices.count && self.writeNumber) {
                                         self->_error = self.writeNumber(item[@"key"], selected)
                                                            ? nil
                                                            : @"Could not save this setting.";
                                         self.needsDisplay = YES;
                                     }
                                   }];
            return;
        }
        BOOL toggle = [item[@"min"] doubleValue] == 0 && [item[@"max"] doubleValue] == 1;
        if (!toggle && [item[@"choices"] count] == 0 && point.x > NSMinX(control) + 30 &&
            point.x < NSMaxX(control) - 30)
            return;
        [self changeRow:index direction:point.x < NSMidX(control) ? -1 : 1];
        return;
    }
}
- (void)controlTextDidChange:(NSNotification*)notification {
    (void)notification;
    _scroll = 0;
    _focusedRow = -1;
    self.needsDisplay = YES;
}

- (BOOL)control:(NSControl*)control
               textView:(NSTextView*)textView
    doCommandBySelector:(SEL)selector {
    (void)control;
    (void)textView;
    if (selector == @selector(cancelOperation:)) {
        [self.nextResponder tryToPerform:selector with:self];
        return YES;
    }
    return NO;
}
- (void)scrollWheel:(NSEvent*)event {
    CGFloat maxScroll = MAX(0, [self visibleRows].count * 48.0 - NSHeight([self listRect]));
    _scroll = MIN(maxScroll, MAX(0, _scroll - event.scrollingDeltaY));
    self.needsDisplay = YES;
}
- (void)keyDown:(NSEvent*)event {
    NSInteger count = [self visibleRows].count;
    if (event.keyCode == 125 || event.keyCode == 126 || event.keyCode == 48) {
        _focusedRow = MAX(0, MIN(count - 1, _focusedRow + (event.keyCode == 126 ? -1 : 1)));
        NSRect rect = [self rowRect:_focusedRow], list = [self listRect];
        if (NSMaxY(rect) > NSMaxY(list))
            _scroll += NSMaxY(rect) - NSMaxY(list);
        if (NSMinY(rect) < NSMinY(list))
            _scroll = MAX(0, _scroll - NSMinY(list) + NSMinY(rect));
        self.needsDisplay = YES;
    } else if (event.keyCode == 123 || event.keyCode == 124 || event.keyCode == 49 ||
               event.keyCode == 36) {
        [self changeRow:_focusedRow direction:event.keyCode == 123 ? -1 : 1];
    } else
        [super keyDown:event];
}
- (void)rightMouseDown:(NSEvent*)event {
    (void)event;
}

- (void)resetCursorRects {
    [super resetCursorRects];
    [self addCursorRect:NSMakeRect(12, 84, 154, groups().count * 38)
                 cursor:NSCursor.pointingHandCursor];
    for (NSInteger index = 0; index < (NSInteger)[self visibleRows].count; ++index) {
        NSRect rect = NSIntersectionRect([self controlRect:index], [self listRect]);
        if (!NSIsEmptyRect(rect))
            [self addCursorRect:rect cursor:NSCursor.pointingHandCursor];
    }
}
@end
