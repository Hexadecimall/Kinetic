#import "utilityPanel.h"
#import "theme.h"
#import <QuartzCore/QuartzCore.h>

@interface KineticPanelClose : NSView
@property(nonatomic, copy) void (^action)(void);
@end
@implementation KineticPanelClose
- (void)drawRect:(NSRect)rect {
    (void)rect;
    NSBezierPath* path = [NSBezierPath bezierPath];
    path.lineWidth = 1.5;
    path.lineCapStyle = NSLineCapStyleRound;
    [path moveToPoint:NSMakePoint(11, 11)];
    [path lineToPoint:NSMakePoint(19, 19)];
    [path moveToPoint:NSMakePoint(19, 11)];
    [path lineToPoint:NSMakePoint(11, 19)];
    [kineticThemeColor(180, 194, 214, 1) setStroke];
    [path stroke];
}
- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}
- (void)mouseDown:(NSEvent*)event {
    (void)event;
    if (self.action)
        self.action();
}
@end

@interface KineticUtilityPanel () {
    NSView* _card;
    NSView* _content;
    KineticPanelClose* _close;
    NSTimer* _timer;
    CGFloat _progress;
    CGFloat _from;
    CGFloat _target;
    NSTimeInterval _started;
    NSTimeInterval _duration;
}
@end

@implementation KineticUtilityPanel
- (instancetype)initWithFrame:(NSRect)frame content:(NSView*)content {
    if ((self = [super initWithFrame:frame])) {
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _card = [[NSView alloc] initWithFrame:NSZeroRect];
        _card.wantsLayer = YES;
        _card.alphaValue = 0;
        _card.layer.cornerRadius = 12;
        _card.layer.masksToBounds = YES;
        _content = content;
        [_card addSubview:content];
        _close = [[KineticPanelClose alloc] initWithFrame:NSMakeRect(0, 0, 30, 30)];
        __weak KineticUtilityPanel* weakSelf = self;
        _close.action = ^{
          if (weakSelf.closeHandler)
              weakSelf.closeHandler();
        };
        [_card addSubview:_close];
        [self addSubview:_card];
    }
    return self;
}
- (BOOL)isFlipped {
    return YES;
}
- (BOOL)acceptsFirstResponder {
    return YES;
}
- (NSRect)cardRect {
    CGFloat width = MIN(960.0, MAX(1.0, NSWidth(self.bounds) - 40.0));
    CGFloat height = MIN(720.0, MAX(1.0, NSHeight(self.bounds) - 40.0));
    return NSMakeRect(floor((NSWidth(self.bounds) - width) / 2),
                      floor((NSHeight(self.bounds) - height) / 2) + (1 - _progress) * 12, width,
                      height);
}
- (void)layout {
    [super layout];
    _card.frame = [self cardRect];
    _content.frame = _card.bounds;
    // The container is unflipped; place the custom close control at its upper right.
    _close.frame = NSMakeRect(NSWidth(_card.bounds) - 42, NSHeight(_card.bounds) - 43, 30, 30);
}
- (void)drawRect:(NSRect)rect {
    (void)rect;
    [[NSColor colorWithWhite:0 alpha:0.28 * _progress] setFill];
    NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);
    [NSGraphicsContext saveGraphicsState];
    NSShadow* shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.32 * _progress];
    shadow.shadowBlurRadius = 24;
    shadow.shadowOffset = NSMakeSize(0, -6);
    [shadow set];
    [kineticThemeColor(44, 54, 68, _progress) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:[self cardRect] xRadius:12 yRadius:12] fill];
    [NSGraphicsContext restoreGraphicsState];
    [kineticThemeColor(82, 102, 130, 0.5 * _progress) setStroke];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect([self cardRect], -0.5, -0.5)
                                     xRadius:12
                                     yRadius:12] stroke];
}
- (void)animateTo:(CGFloat)target duration:(NSTimeInterval)duration {
    [_timer invalidate];
    _from = _progress;
    _target = target;
    _duration = MAX(0.001, duration);
    _started = NSProcessInfo.processInfo.systemUptime;
    if (duration <= 0) {
        _progress = target;
        _card.alphaValue = target;
        self.needsLayout = YES;
        self.needsDisplay = YES;
        if (target == 0)
            [self removeFromSuperview];
        return;
    }
    _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                              target:self
                                            selector:@selector(step:)
                                            userInfo:nil
                                             repeats:YES];
}
- (void)step:(NSTimer*)timer {
    CGFloat t = MIN(1.0, (NSProcessInfo.processInfo.systemUptime - _started) / _duration);
    CGFloat eased = 1 - pow(1 - t, 3);
    _progress = _from + (_target - _from) * eased;
    _card.alphaValue = _progress;
    self.needsLayout = YES;
    self.needsDisplay = YES;
    if (t >= 1) {
        [timer invalidate];
        _timer = nil;
        if (_target == 0)
            [self removeFromSuperview];
    }
}
- (void)presentAnimated:(BOOL)animated duration:(NSTimeInterval)duration {
    [self animateTo:1 duration:animated ? duration : 0];
    [self.window makeFirstResponder:_content];
}
- (void)dismissAnimated:(BOOL)animated duration:(NSTimeInterval)duration {
    [self animateTo:0 duration:animated ? duration : 0];
}
- (void)mouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(point, [self cardRect]) && self.closeHandler)
        self.closeHandler();
}
- (void)keyDown:(NSEvent*)event {
    if (event.keyCode == 53 && self.closeHandler)
        self.closeHandler();
    else
        [super keyDown:event];
}
- (void)cancelOperation:(id)sender {
    (void)sender;
    if (self.closeHandler)
        self.closeHandler();
}
- (void)rightMouseDown:(NSEvent*)event {
    (void)event;
}
- (void)scrollWheel:(NSEvent*)event {
    (void)event;
}
@end
