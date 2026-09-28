#import "toolPrompt.h"
#import "theme.h"

@interface KineticToolPrompt () {
    BOOL _yesFocused;
}
@end

@implementation KineticToolPrompt
- (BOOL)isFlipped {
    return YES;
}
- (BOOL)acceptsFirstResponder {
    return YES;
}
- (NSRect)panelRect {
    CGFloat width = MIN(540, NSWidth(self.bounds) - 32);
    return NSMakeRect((NSWidth(self.bounds) - width) / 2, (NSHeight(self.bounds) - 270) / 2, width,
                      270);
}
- (NSRect)buttonRect:(BOOL)yes {
    NSRect panel = [self panelRect];
    return NSMakeRect(NSMaxX(panel) - (yes ? 100 : 190), NSMaxY(panel) - 48, 76, 30);
}
- (void)setMessage:(NSString*)message {
    _message = [message copy];
    self.needsDisplay = YES;
}
- (void)setBusy:(BOOL)busy {
    _busy = busy;
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[[NSColor blackColor] colorWithAlphaComponent:0.35] setFill];
    NSRectFill(self.bounds);
    NSRect panel = [self panelRect];
    [kineticThemeColor(40, 50, 65, 1) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:panel xRadius:12 yRadius:12] fill];
    NSDictionary* text = @{
        NSFontAttributeName : [NSFont systemFontOfSize:13],
        NSForegroundColorAttributeName : kineticThemeColor(225, 233, 243, 1)
    };
    [@"C/C++ tools" drawAtPoint:NSMakePoint(NSMinX(panel) + 24, NSMinY(panel) + 22)
                 withAttributes:text];
    [self.message ?: @""
            drawInRect:NSMakeRect(NSMinX(panel) + 24, NSMinY(panel) + 56, NSWidth(panel) - 48, 156)
        withAttributes:text];
    for (NSNumber* value in @[ @NO, @YES ]) {
        BOOL yes = value.boolValue;
        NSRect rect = [self buttonRect:yes];
        [kineticThemeColor(yes ? 65 : 52, yes ? 104 : 65, yes ? 166 : 82, _busy ? 0.4 : 1) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:5 yRadius:5] fill];
        if (!_busy && self.window.firstResponder == self && _yesFocused == yes) {
            [kineticThemeColor(140, 180, 240, 1) setStroke];
            [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:5 yRadius:5] stroke];
        }
        NSString* title = yes ? @"Yes" : @"No";
        NSSize size = [title sizeWithAttributes:text];
        [title drawAtPoint:NSMakePoint(NSMidX(rect) - size.width / 2,
                                       NSMidY(rect) - size.height / 2)
            withAttributes:text];
    }
}
- (void)mouseDown:(NSEvent*)event {
    if (_busy)
        return;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(point, [self buttonRect:YES]))
        self.answer(YES);
    else if (NSPointInRect(point, [self buttonRect:NO]))
        self.answer(NO);
}
- (void)keyDown:(NSEvent*)event {
    if (_busy || self.answer == nil)
        return;
    if (event.keyCode == 53)
        self.answer(NO);
    else if (event.keyCode == 48 || event.keyCode == 123 || event.keyCode == 124) {
        _yesFocused = !_yesFocused;
        self.needsDisplay = YES;
    } else if (event.keyCode == 36 || event.keyCode == 49)
        self.answer(_yesFocused);
}
@end
