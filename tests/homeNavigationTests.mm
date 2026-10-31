#import "homeView.h"
#import "trafficBar.h"

@interface KineticHomeView (NavigationTest)
- (void)rebuildActionRects;
@end

@interface NSView (MenuNavigationTest)
- (instancetype)initWithFrame:(NSRect)frame owner:(KineticTrafficBar*)owner;
@end

@interface NavigationHandler : NSObject
@property(nonatomic) NSUInteger settingsCount;
@property(nonatomic, copy) NSString* command;
@end
@implementation NavigationHandler
- (void)showSettings {
    self.settingsCount += 1;
}
- (void)executePluginCommand:(NSString*)command {
    self.command = command;
}
@end

int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NavigationHandler* handler = [[NavigationHandler alloc] init];
        KineticHomeView* home = [[KineticHomeView alloc] initWithFrame:NSMakeRect(0, 0, 900, 600)];
        home.commandHandler = (id<KineticCommandHandler>)handler;
        [home rebuildActionRects];
        NSArray* titles = [home valueForKey:@"actionTitles"];
        NSUInteger settingsIndex = [titles indexOfObject:@"Settings…"];
        if (settingsIndex == NSNotFound)
            return 1;
        NSArray<NSValue*>* rects = [home valueForKey:@"actionRects"];
        NSRect rect = rects[settingsIndex].rectValue;
        NSPoint location = [home convertPoint:NSMakePoint(NSMidX(rect), NSMidY(rect)) toView:nil];
        NSEvent* click = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                            location:location
                                       modifierFlags:0
                                           timestamp:0
                                        windowNumber:0
                                             context:nil
                                         eventNumber:0
                                          clickCount:1
                                            pressure:1];
        [home mouseDown:click];
        if (handler.settingsCount != 1)
            return 2;

        KineticTrafficBar* bar =
            [[KineticTrafficBar alloc] initWithFrame:NSMakeRect(0, 0, 900, 34)];
        bar.commandHandler = (id<KineticCommandHandler>)handler;
        bar.fileMenuItems = @[ @{@"id" : @"test.command", @"title" : @"Test Command"} ];
        NSView* menu = [[NSClassFromString(@"KineticMenuOverlay") alloc] initWithFrame:home.bounds
                                                                                 owner:bar];
        NSEvent* enter = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                          location:NSZeroPoint
                                     modifierFlags:0
                                         timestamp:0
                                      windowNumber:0
                                           context:nil
                                        characters:@"\r"
                       charactersIgnoringModifiers:@"\r"
                                         isARepeat:NO
                                           keyCode:36];
        [menu setValue:@10 forKey:@"selectedRow"];
        [menu keyDown:enter];
        if (handler.settingsCount != 2)
            return 3;
        [menu setValue:@12 forKey:@"selectedRow"];
        [menu keyDown:enter];
        if (![handler.command isEqualToString:@"test.command"])
            return 4;
    }
    return 0;
}
