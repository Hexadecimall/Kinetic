#import "theme.h"

namespace {
NSString* currentTheme = nil;
NSDictionary<NSString*, NSColor*>* currentPalette = nil;

NSString* themePath() {
    return [NSHomeDirectory() stringByAppendingPathComponent:@".kinetic/theme.toml"];
}

NSString* roleForSource(uint32_t rgb) {
    // Explicit compatibility map for the existing renderer's default colors.
    // Each alternate palette controls named roles rather than transforming RGB values.
    switch (rgb) {
    case 0x05080d:
    case 0x050910:
    case 0x080c13:
    case 0x080d15:
    case 0x090d14:
        return @"shadow";
    case 0x1d2633:
    case 0x1e2632:
    case 0x202a39:
    case 0x222b39:
    case 0x232c39:
    case 0x262f3d:
    case 0x27303d:
    case 0x273b5b:
    case 0x283343:
        return @"input";
    case 0x232b37:
    case 0x232c3a:
    case 0x273140:
        return @"popup";
    case 0x2a3340:
        return @"panel";
    case 0x2c3542:
        return @"rail";
    case 0x2c3644:
    case 0x2f3b4c:
    case 0x303b4a:
    case 0x323d4c:
    case 0x35404f:
    case 0x374353:
    case 0x3a4554:
        return @"surface";
    case 0x2f3947:
        return @"background";
    case 0x3b4c69:
    case 0x3d5378:
    case 0x42597d:
    case 0x446aa4:
        return @"selection";
    case 0x3e4b5d:
    case 0x435163:
    case 0x49576a:
    case 0x4a5769:
        return @"hover";
    case 0x4c5b70:
    case 0x4d607d:
    case 0x4d6281:
    case 0x4e5e73:
    case 0x4f5e72:
    case 0x516584:
    case 0x526682:
    case 0x536784:
    case 0x576c8b:
    case 0x5d6d82:
    case 0x6a809e:
    case 0x455265:
    case 0x455469:
    case 0x475467:
    case 0x4b596d:
    case 0x4b5a6f:
    case 0x4b5c76:
        return @"border";
    case 0x4d8dff:
    case 0x5b97ff:
        return @"accent";
    case 0x669eff:
    case 0x679eff:
    case 0x6fa6ff:
    case 0x70a6ff:
    case 0x82b2ff:
    case 0x8bb3fa:
        return @"accentHover";
    case 0x73c7d1:
        return @"type";
    case 0x768497:
    case 0x7a8ba0:
    case 0x7c91ae:
    case 0x7d8ca1:
    case 0x7e8ea3:
    case 0x8490a1:
    case 0x8492a6:
    case 0x899db9:
    case 0x8b9bb1:
    case 0x6b7789:
        return @"textMuted";
    case 0x76aafa:
        return @"keyword";
    case 0x8595a9:
        return @"comment";
    case 0x8e9eb4:
    case 0x90a0b4:
    case 0x919daf:
    case 0x919fb3:
    case 0x91a2b8:
    case 0x94a1b2:
    case 0x94a5bd:
    case 0x97a5b8:
    case 0x97a8be:
    case 0x99aeca:
    case 0x9ba7b8:
    case 0x9baabd:
    case 0x9bb3d6:
    case 0x9bb5dc:
    case 0x9dabbe:
    case 0x9eadc1:
    case 0xa0afc3:
    case 0xa4b3c6:
    case 0xa5b1c1:
    case 0xaab8c9:
    case 0xabb8c9:
    case 0xabb9cc:
    case 0xaebed3:
    case 0xb4c2d6:
    case 0xb8c4d6:
    case 0xbec9d7:
    case 0xccdaec:
        return @"textSecondary";
    case 0x8ebef8:
        return @"key";
    case 0xa7d3ac:
        return @"string";
    case 0xcaabe9:
        return @"constant";
    case 0xd0ddf6:
        return @"function";
    case 0xd7e0ed:
    case 0xd7e2f0:
    case 0xd8e5f6:
    case 0xdae1eb:
    case 0xdae2ed:
    case 0xdae3ef:
    case 0xdce4ef:
    case 0xdce5f1:
    case 0xdee6f2:
    case 0xe1eaf7:
    case 0xe2e8f1:
    case 0xe2e9f2:
    case 0xe2ebf8:
    case 0xe2edfc:
    case 0xe3ebf7:
    case 0xe5ecf6:
    case 0xe8eef7:
    case 0xe8eff9:
    case 0xe9f0fa:
    case 0xeaf1fc:
    case 0xebf0f7:
    case 0xebf1f9:
    case 0xedf4fd:
    case 0xeff4fb:
    case 0xeff5fe:
    case 0xf4f7fc:
    case 0xf5f8fc:
    case 0xf7f9fc:
        return @"text";
    case 0xf5a970:
        return @"number";
    case 0xf6b85f:
    case 0xf6c274:
        return @"warning";
    case 0xf7b786:
        return @"variable";
    case 0xff7177:
    case 0xff7a61:
    case 0xff959a:
        return @"error";
    case 0xff7a3d:
    case 0xff915c:
        return @"energy";
    default:
        return nil;
    }
}

void loadPalette() {
    NSString* filename = [currentTheme isEqualToString:@"kinetic-dark"]
                             ? currentTheme
                             : [@"kinetic-" stringByAppendingString:currentTheme];
    NSURL* url = [NSBundle.mainBundle URLForResource:filename
                                       withExtension:@"toml"
                                        subdirectory:@"themes"];
    NSMutableDictionary* palette = [NSMutableDictionary dictionary];
    if (![currentTheme isEqualToString:@"kinetic-dark"] && url != nil) {
        [palette
            addEntriesFromDictionary:kineticReadThemePalette([NSData dataWithContentsOfURL:url])];
    }
    NSString* custom = [[NSHomeDirectory() stringByAppendingPathComponent:@".kinetic/themes"]
        stringByAppendingPathComponent:[filename stringByAppendingPathExtension:@"toml"]];
    [palette
        addEntriesFromDictionary:kineticReadThemePalette([NSData dataWithContentsOfFile:custom])];
    currentPalette = palette;
}

void loadTheme() {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      NSString* saved = [NSString stringWithContentsOfFile:themePath()
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
      NSRegularExpression* pattern = [NSRegularExpression
          regularExpressionWithPattern:
              @"(?m)^name[ \\t]*=[ \\t]*\\\"(kinetic-dark|midnight|graphite)\\\"[ \\t]*(?:#.*)?$"
                               options:0
                                 error:nil];
      NSTextCheckingResult* match = [pattern firstMatchInString:saved ?: @""
                                                        options:0
                                                          range:NSMakeRange(0, saved.length)];
      currentTheme = match ? [saved substringWithRange:[match rangeAtIndex:1]] : @"kinetic-dark";
      loadPalette();
    });
}
} // namespace

NSDictionary<NSString*, NSColor*>* kineticReadThemePalette(NSData* data) {
    NSMutableDictionary* palette = [NSMutableDictionary dictionary];
    NSString* contents =
        data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    BOOL inPalette = NO;
    NSRegularExpression* entry = [NSRegularExpression
        regularExpressionWithPattern:
            @"^([A-Za-z][A-Za-z0-9]*)[ \\t]*=[ \\t]*\\\"#([0-9a-fA-F]{6})\\\"[ \\t]*(?:#.*)?$"
                             options:0
                               error:nil];
    for (NSString* line in
         [contents componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString* text =
            [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([text hasPrefix:@"["]) {
            inPalette = [text isEqualToString:@"[colors]"] || [text isEqualToString:@"[syntax]"];
            continue;
        }
        if (!inPalette)
            continue;
        NSTextCheckingResult* match = [entry firstMatchInString:text
                                                        options:0
                                                          range:NSMakeRange(0, text.length)];
        if (match == nil)
            continue;
        unsigned rgb = 0;
        [[NSScanner scannerWithString:[text substringWithRange:[match rangeAtIndex:2]]]
            scanHexInt:&rgb];
        palette[[text substringWithRange:[match rangeAtIndex:1]]] =
            [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255.0
                                green:((rgb >> 8) & 255) / 255.0
                                 blue:(rgb & 255) / 255.0
                                alpha:1.0];
    }
    return palette;
}

NSString* kineticThemeName(void) {
    loadTheme();
    return currentTheme;
}

void kineticSetThemeName(NSString* name) {
    loadTheme();
    if (![name isEqualToString:@"kinetic-dark"] && ![name isEqualToString:@"midnight"] &&
        ![name isEqualToString:@"graphite"])
        return;
    currentTheme = [name copy];
    loadPalette();
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
    uint32_t rgb = ((uint32_t)red << 16) | ((uint32_t)green << 8) | (uint32_t)blue;
    NSString* role = roleForSource(rgb);
    NSColor* fallback = [NSColor colorWithSRGBRed:red / 255.0
                                            green:green / 255.0
                                             blue:blue / 255.0
                                            alpha:alpha];
    if (role == nil)
        return fallback;
    NSColor* color = currentPalette[role];
    return color ? [color colorWithAlphaComponent:alpha] : fallback;
}

void kineticRefreshThemeInView(NSView* view) {
    view.needsDisplay = YES;
    if ([view isKindOfClass:NSTextField.class]) {
        NSTextField* field = (NSTextField*)view;
        field.textColor = kineticThemeColor(226, 233, 242, 1.0);
        if (field.placeholderString.length > 0) {
            field.placeholderAttributedString = [[NSAttributedString alloc]
                initWithString:field.placeholderString
                    attributes:@{
                        NSForegroundColorAttributeName : kineticThemeColor(139, 155, 177, 1.0),
                        NSFontAttributeName : field.font ?: [NSFont systemFontOfSize:12.0],
                    }];
        }
    }
    for (NSView* child in view.subviews)
        kineticRefreshThemeInView(child);
}
