#import "theme.h"

namespace {
NSString* currentTheme = nil;

NSString* themePath() {
    return [NSHomeDirectory() stringByAppendingPathComponent:@".kinetic/theme.toml"];
}

void loadTheme() {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      NSString* saved = [NSString stringWithContentsOfFile:themePath()
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
      currentTheme = [saved containsString:@"midnight"]   ? @"midnight"
                     : [saved containsString:@"graphite"] ? @"graphite"
                                                          : @"kinetic-dark";
    });
}
} // namespace

NSString* kineticThemeName(void) {
    loadTheme();
    return currentTheme;
}

void kineticSetThemeName(NSString* name) {
    loadTheme();
    if (![name isEqualToString:@"kinetic-dark"] && ![name isEqualToString:@"midnight"] &&
        ![name isEqualToString:@"graphite"]) {
        return;
    }
    currentTheme = [name copy];
    NSString* directory = [NSHomeDirectory() stringByAppendingPathComponent:@".kinetic"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    NSString* contents =
        [NSString stringWithFormat:@"# Kinetic color theme\nname = \"%@\"\n", name];
    [contents writeToFile:themePath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

NSColor* kineticThemeColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha) {
    loadTheme();
    if (![currentTheme isEqualToString:@"kinetic-dark"]) {
        CGFloat high = MAX(red, MAX(green, blue));
        CGFloat low = MIN(red, MIN(green, blue));
        // Preserve legible text and semantic/accent colors; recolor the shared surfaces.
        if (high < 165.0 && high - low < 48.0) {
            CGFloat brightness = (red + green + blue) / 3.0;
            CGFloat offset = brightness - 46.0;
            if ([currentTheme isEqualToString:@"midnight"]) {
                red = MAX(13.0, 19.0 + offset * 0.62);
                green = MAX(18.0, 26.0 + offset * 0.73);
                blue = MAX(29.0, 42.0 + offset * 0.85);
            } else {
                red = MAX(20.0, 34.0 + offset * 0.76);
                green = MAX(20.0, 33.0 + offset * 0.76);
                blue = MAX(22.0, 35.0 + offset * 0.78);
            }
        }
    }
    return [NSColor colorWithSRGBRed:MIN(255.0, red) / 255.0
                               green:MIN(255.0, green) / 255.0
                                blue:MIN(255.0, blue) / 255.0
                               alpha:alpha];
}
