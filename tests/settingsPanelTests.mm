#import "settingsPanel.h"
#import "utilityPanel.h"

@interface KineticSettingsPanel (Test)
- (NSArray*)visibleRows;
- (NSRect)listRect;
- (NSRect)rowRect:(NSInteger)index;
- (NSRect)controlRect:(NSInteger)index;
- (void)changeRow:(NSInteger)index direction:(NSInteger)direction;
- (CGFloat)switchProgress:(NSString*)key value:(double)value;
@end

@interface KineticUtilityPanel (Test)
- (NSRect)cardRect;
@end

static BOOL check(BOOL passed, NSString* message) {
    if (!passed)
        NSLog(@"Settings test failed: %@", message);
    return passed;
}

int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        BOOL passed = YES;
        NSMutableSet* keys = [NSMutableSet set];
        for (NSDictionary* row in kineticSettingsRows()) {
            passed &= check(![keys containsObject:row[@"key"]], @"unique preference key");
            [keys addObject:row[@"key"]];
            passed &= check([row[@"min"] doubleValue] < [row[@"max"] doubleValue], @"valid limits");
        }
        passed &= check(keys.count == 26, @"all settings exposed");
        KineticSettingsPanel* settings =
            [[KineticSettingsPanel alloc] initWithFrame:NSMakeRect(0, 0, 680, 406)];
        NSMutableDictionary* values = [@{
            @"interface.motion.enabled" : @1,
            @"interface.motion.duration" : @180,
            @"editor.gutter.lineNumbers" : @1,
            @"editor.text.fontSize" : @13
        } mutableCopy];
        settings.readNumber = ^double(NSString* key) {
          return [values[key] doubleValue];
        };
        settings.writeNumber = ^BOOL(NSString* key, double value) {
          values[key] = @(value);
          return YES;
        };
        NSRect control = [settings controlRect:2];
        passed &= check(NSContainsRect([settings rowRect:2], control),
                        @"stepper fits row at minimum width");
        passed &= check(NSWidth(control) == 120, @"compact stepper");
        [settings changeRow:2 direction:1];
        passed &=
            check([values[@"editor.text.fontSize"] doubleValue] == 14, @"stepper updates value");
        [settings changeRow:5 direction:1];
        passed &= check([values[@"editor.gutter.lineNumbers"] doubleValue] == 0,
                        @"toggle updates value immediately");
        CGFloat position = [settings switchProgress:@"editor.gutter.lineNumbers" value:0];
        passed &= check(NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion
                            ? position == 0
                            : position > 0 && position <= 1,
                        @"toggle animates or respects Reduced Motion");
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
        passed &= check([settings switchProgress:@"editor.gutter.lineNumbers" value:0] == 0,
                        @"toggle settles");
        NSTextField* search = [settings valueForKey:@"search"];
        search.stringValue = @"caret";
        values[@"editor.caret.stretch"] = @0.6;
        [settings changeRow:2 direction:1];
        passed &= check(fabs([values[@"editor.caret.stretch"] doubleValue] - 0.7) < 0.0001,
                        @"fractional zero-to-one settings use a stepper");
        NSView* host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 720, 446)];
        KineticUtilityPanel* panel = [[KineticUtilityPanel alloc] initWithFrame:host.bounds
                                                                        content:settings];
        [host addSubview:panel];
        [panel presentAnimated:NO duration:0];
        passed &=
            check(NSContainsRect(host.bounds, [panel cardRect]), @"panel fits minimum window");
        [panel dismissAnimated:NO duration:0];
        passed &= check(panel.superview == nil, @"close removes overlay");
        [host addSubview:panel];
        [panel presentAnimated:NO duration:0];
        [panel dismissAnimated:YES duration:0.08];
        passed &= check(panel.superview == host, @"closing animation keeps overlay alive");
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
        passed &= check(panel.superview == nil, @"animated close completes");
        return passed ? 0 : 1;
    }
}
