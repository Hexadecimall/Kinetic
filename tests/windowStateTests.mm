#import "windowState.h"
#include <cassert>

int main() {
    @autoreleasepool {
        NSRect primary = NSMakeRect(0, 24, 1440, 876);
        NSRect secondary = NSMakeRect(-1920, 0, 1920, 1080);
        NSArray* screens = @[ [NSValue valueWithRect:primary], [NSValue valueWithRect:secondary] ];
        NSSize minimum = NSMakeSize(720, 480);
        NSRect saved = NSMakeRect(-1800, 100, 1000, 700);
        assert(NSEqualRects(kineticVisibleWindowFrame(saved, screens, minimum), saved));
        NSRect restored = kineticVisibleWindowFrame(saved, @[ screens[0] ], minimum);
        assert(NSContainsRect(primary, restored));
        assert(NSEqualSizes(restored.size, saved.size));
        restored = kineticVisibleWindowFrame(NSMakeRect(100, 100, 4000, 3000), screens, minimum);
        assert(NSContainsRect(primary, restored));
        restored = kineticVisibleWindowFrame(NSMakeRect(300, 200, 10, 10), screens, minimum);
        assert(NSEqualSizes(restored.size, minimum));
    }
    return 0;
}
