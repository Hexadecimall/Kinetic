#import "theme.h"
#include <cassert>
#include <cmath>
#include <cstdio>

double luminance(NSColor* color) {
    color = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    auto linear = [](double c) {
        return c <= 0.04045 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) +
           0.0722 * linear(color.blueComponent);
}

int main(int argc, const char** argv) {
    @autoreleasepool {
        assert(argc == 2);
        NSString* directory = [NSString stringWithUTF8String:argv[1]];
        for (NSString* name in @[ @"kinetic-midnight", @"kinetic-graphite" ]) {
            NSString* path =
                [directory stringByAppendingPathComponent:[name stringByAppendingString:@".toml"]];
            NSDictionary* palette = kineticReadThemePalette([NSData dataWithContentsOfFile:path]);
            assert(palette.count == 27);
            NSArray* textRoles = @[
                @"text", @"textSecondary", @"textMuted", @"keyword", @"string", @"comment",
                @"number", @"constant", @"type", @"function", @"variable", @"key", @"error",
                @"warning"
            ];
            for (NSString* role in textRoles) {
                double ratio =
                    (luminance(palette[role]) + 0.05) / (luminance(palette[@"background"]) + 0.05);
                if (ratio < 4.5) {
                    fprintf(stderr, "%s %s contrast %.2f is below 4.5\n", name.UTF8String,
                            role.UTF8String, ratio);
                    return 1;
                }
            }
            double buttonRatio =
                (luminance(palette[@"text"]) + 0.05) / (luminance(palette[@"accent"]) + 0.05);
            assert(buttonRatio >= 4.5);
        }
        NSData* invalid =
            [@"[colors]\ntext = \"#ZZZZZZ\"\nbackground = \"#123456\"\n[metrics]\nignored = "
             @"\"#ABCDEF\"\n" dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary* palette = kineticReadThemePalette(invalid);
        assert(palette.count == 1 && palette[@"background"] != nil);
    }
    return 0;
}
