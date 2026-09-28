#import "windowState.h"

NSRect kineticVisibleWindowFrame(NSRect frame, NSArray<NSValue*>* screens, NSSize minimumSize) {
    if (screens.count == 0) {
        return frame;
    }
    NSRect visible = screens.firstObject.rectValue;
    CGFloat largestOverlap = 0.0;
    for (NSValue* value in screens) {
        NSRect candidate = value.rectValue;
        NSRect overlap = NSIntersectionRect(frame, candidate);
        CGFloat area = NSWidth(overlap) * NSHeight(overlap);
        if (area > largestOverlap) {
            largestOverlap = area;
            visible = candidate;
        }
    }
    frame.size.width = MIN(NSWidth(visible), MAX(minimumSize.width, NSWidth(frame)));
    frame.size.height = MIN(NSHeight(visible), MAX(minimumSize.height, NSHeight(frame)));
    frame.origin.x = MAX(NSMinX(visible), MIN(NSMaxX(visible) - NSWidth(frame), NSMinX(frame)));
    frame.origin.y = MAX(NSMinY(visible), MIN(NSMaxY(visible) - NSHeight(frame), NSMinY(frame)));
    return frame;
}

@implementation KineticWindowState {
    __weak NSWindow* _window;
    NSTimer* _saveTimer;
    BOOL _fullscreenTransition;
    BOOL _restoring;
}

- (instancetype)initWithWindow:(NSWindow*)window {
    self = [super init];
    if (self) {
        _window = window;
        window.delegate = self;
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(applicationWillTerminate:)
                                                   name:NSApplicationWillTerminateNotification
                                                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [_saveTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSString*)statePath {
    return [NSHomeDirectory() stringByAppendingPathComponent:@".kinetic/window.json"];
}

- (BOOL)restore {
    NSData* data = [NSData dataWithContentsOfFile:[self statePath]];
    id state =
        data == nil ? nil : [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![state isKindOfClass:NSDictionary.class]) {
        return NO;
    }
    for (NSString* key in @[ @"x", @"y", @"width", @"height" ]) {
        if (![state[key] isKindOfClass:NSNumber.class] || !isfinite([state[key] doubleValue])) {
            return NO;
        }
    }
    NSRect frame = NSMakeRect([state[@"x"] doubleValue], [state[@"y"] doubleValue],
                              [state[@"width"] doubleValue], [state[@"height"] doubleValue]);
    if (NSWidth(frame) <= 0.0 || NSHeight(frame) <= 0.0) {
        return NO;
    }
    NSMutableArray<NSValue*>* screens = [NSMutableArray array];
    for (NSScreen* screen in NSScreen.screens) {
        [screens addObject:[NSValue valueWithRect:screen.visibleFrame]];
    }
    _restoring = YES;
    [_window setFrame:kineticVisibleWindowFrame(frame, screens, _window.minSize) display:NO];
    _restoring = NO;
    return YES;
}

- (void)save {
    [_saveTimer invalidate];
    _saveTimer = nil;
    if (_window == nil || _restoring || _fullscreenTransition || _window.miniaturized ||
        (_window.styleMask & NSWindowStyleMaskFullScreen) != 0) {
        return;
    }
    NSRect frame = _window.frame;
    NSDictionary* state = @{
        @"x" : @(NSMinX(frame)),
        @"y" : @(NSMinY(frame)),
        @"width" : @(NSWidth(frame)),
        @"height" : @(NSHeight(frame)),
    };
    NSString* path = [self statePath];
    NSError* error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:&error]) {
        NSLog(@"Could not save window layout: %@", error.localizedDescription);
        return;
    }
    NSData* data = [NSJSONSerialization dataWithJSONObject:state
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];
    if (data == nil || ![data writeToFile:path options:NSDataWritingAtomic error:&error]) {
        NSLog(@"Could not save window layout: %@", error.localizedDescription);
    }
}

- (void)scheduleSave {
    if (_restoring || _fullscreenTransition) {
        return;
    }
    [_saveTimer invalidate];
    __weak KineticWindowState* weakSelf = self;
    _saveTimer = [NSTimer scheduledTimerWithTimeInterval:0.3
                                                 repeats:NO
                                                   block:^(NSTimer* timer) {
                                                     (void)timer;
                                                     [weakSelf save];
                                                   }];
}

- (void)windowDidMove:(NSNotification*)notification {
    (void)notification;
    [self scheduleSave];
}

- (void)windowDidResize:(NSNotification*)notification {
    (void)notification;
    [self scheduleSave];
}

- (void)windowWillEnterFullScreen:(NSNotification*)notification {
    (void)notification;
    [self save];
    _fullscreenTransition = YES;
}

- (void)windowDidEnterFullScreen:(NSNotification*)notification {
    (void)notification;
    _fullscreenTransition = NO;
}

- (void)windowWillExitFullScreen:(NSNotification*)notification {
    (void)notification;
    _fullscreenTransition = YES;
}

- (void)windowDidExitFullScreen:(NSNotification*)notification {
    (void)notification;
    _fullscreenTransition = NO;
    [self scheduleSave];
}

- (void)windowWillClose:(NSNotification*)notification {
    (void)notification;
    [self save];
}

- (void)applicationWillTerminate:(NSNotification*)notification {
    (void)notification;
    [self save];
}
@end
