#import "cloneDialog.h"
#import "theme.h"

namespace {
NSColor* cloneColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha = 1.0) {
    return kineticThemeColor(red, green, blue, alpha);
}
} // namespace

@interface KineticCloneDialog () <NSTextFieldDelegate> {
    NSTextField* _urlField;
}
@end

@implementation KineticCloneDialog

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _status = @"Clone a repository into a folder you choose.";
        _urlField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _urlField.placeholderString = @"https://github.com/owner/repository.git";
        _urlField.font = [NSFont systemFontOfSize:13.0];
        _urlField.textColor = cloneColor(232, 239, 249);
        _urlField.backgroundColor = NSColor.clearColor;
        _urlField.drawsBackground = NO;
        _urlField.bordered = NO;
        _urlField.focusRingType = NSFocusRingTypeNone;
        _urlField.delegate = self;
        [self addSubview:_urlField];
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (NSRect)panelRect {
    CGFloat width = MIN(550.0, NSWidth(self.bounds) - 40.0);
    return NSMakeRect(floor((NSWidth(self.bounds) - width) * 0.5),
                      floor((NSHeight(self.bounds) - 240.0) * 0.42), width, 240.0);
}

- (NSRect)cancelRect {
    NSRect panel = [self panelRect];
    return NSMakeRect(NSMaxX(panel) - 212.0, NSMaxY(panel) - 53.0, 82.0, 31.0);
}

- (NSRect)continueRect {
    NSRect panel = [self panelRect];
    return NSMakeRect(NSMaxX(panel) - 119.0, NSMaxY(panel) - 53.0, 96.0, 31.0);
}

- (void)layout {
    [super layout];
    NSRect panel = [self panelRect];
    _urlField.frame =
        NSMakeRect(NSMinX(panel) + 31.0, NSMinY(panel) + 101.0, NSWidth(panel) - 62.0, 23.0);
}

- (NSString*)repositoryUrl {
    return _urlField.stringValue;
}

- (void)setRepositoryUrl:(NSString*)repositoryUrl {
    _urlField.stringValue = repositoryUrl ?: @"";
}

- (void)setStatus:(NSString*)status {
    _status = [status copy] ?: @"";
    self.needsDisplay = YES;
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    _urlField.enabled = !busy;
    self.needsDisplay = YES;
}

- (void)focusUrl {
    [self.window makeFirstResponder:_urlField];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [cloneColor(8, 13, 21, 0.67) setFill];
    NSRectFill(self.bounds);
    NSRect panel = [self panelRect];
    [cloneColor(39, 49, 64) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:panel xRadius:8.0 yRadius:8.0] fill];
    [cloneColor(83, 103, 132, 0.8) setStroke];
    [[NSBezierPath bezierPathWithRoundedRect:panel xRadius:8.0 yRadius:8.0] stroke];
    [@"Clone Repository" drawAtPoint:NSMakePoint(NSMinX(panel) + 25.0, NSMinY(panel) + 24.0)
                      withAttributes:@{
                          NSFontAttributeName : [NSFont systemFontOfSize:19.0
                                                                  weight:NSFontWeightSemibold],
                          NSForegroundColorAttributeName : cloneColor(235, 241, 249),
                      }];
    [@"Repository URL" drawAtPoint:NSMakePoint(NSMinX(panel) + 26.0, NSMinY(panel) + 76.0)
                    withAttributes:@{
                        NSFontAttributeName : [NSFont systemFontOfSize:11.0
                                                                weight:NSFontWeightMedium],
                        NSForegroundColorAttributeName : cloneColor(155, 179, 214),
                    }];
    NSRect field =
        NSMakeRect(NSMinX(panel) + 23.0, NSMinY(panel) + 96.0, NSWidth(panel) - 46.0, 35.0);
    [cloneColor(32, 42, 57) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:field xRadius:5.0 yRadius:5.0] fill];
    [cloneColor(77, 98, 129) setStroke];
    [[NSBezierPath bezierPathWithRoundedRect:field xRadius:5.0 yRadius:5.0] stroke];
    [_status drawInRect:NSMakeRect(NSMinX(panel) + 25.0, NSMinY(panel) + 143.0,
                                   NSWidth(panel) - 50.0, 36.0)
         withAttributes:@{
             NSFontAttributeName : [NSFont systemFontOfSize:11.5],
             NSForegroundColorAttributeName : cloneColor(171, 185, 204),
         }];
    for (NSNumber* button in @[ @NO, @YES ]) {
        BOOL primary = button.boolValue;
        NSRect rect = primary ? [self continueRect] : [self cancelRect];
        [cloneColor(primary ? 74 : 57, primary ? 129 : 70, primary ? 222 : 89,
                    _busy && primary ? 0.45 : 0.95) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:5.0 yRadius:5.0] fill];
        NSString* title = primary ? @"Choose…" : (_busy ? @"Stop" : @"Cancel");
        NSDictionary* style = @{
            NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName : cloneColor(237, 244, 253),
        };
        NSSize size = [title sizeWithAttributes:style];
        [title drawAtPoint:NSMakePoint(NSMidX(rect) - size.width * 0.5,
                                       NSMidY(rect) - size.height * 0.5)
            withAttributes:style];
    }
}

- (void)chooseDestination {
    if (!_busy) {
        [self.delegate cloneDialog:self didRequestDestinationForUrl:_urlField.stringValue];
    }
}

- (void)mouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(point, [self continueRect])) {
        [self chooseDestination];
    } else if (NSPointInRect(point, [self cancelRect]) || !NSPointInRect(point, [self panelRect])) {
        [self.delegate cloneDialogDidCancel:self];
    } else {
        [self focusUrl];
    }
}

- (BOOL)control:(NSControl*)control
               textView:(NSTextView*)textView
    doCommandBySelector:(SEL)selector {
    (void)control;
    (void)textView;
    if (selector == @selector(insertNewline:)) {
        [self chooseDestination];
    } else if (selector == @selector(cancelOperation:)) {
        [self.delegate cloneDialogDidCancel:self];
    } else {
        return NO;
    }
    return YES;
}

@end
