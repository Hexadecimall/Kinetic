#import <Foundation/Foundation.h>

#import "pluginHost.h"

@interface TestPluginDelegate : NSObject <KineticPluginHostDelegate>
@property(nonatomic) double letterSpacing;
@property(nonatomic, copy) NSString* document;
@end

@implementation TestPluginDelegate

- (BOOL)pluginHost:(KineticPluginHost*)host setNumber:(double)value property:(NSString*)property {
    (void)host;
    if (![property isEqualToString:@"editor.text.letterSpacing"] || value < -2.0 || value > 8.0) {
        return NO;
    }
    self.letterSpacing = value;
    return YES;
}

- (BOOL)pluginHost:(KineticPluginHost*)host getNumber:(double*)value property:(NSString*)property {
    (void)host;
    if (![property isEqualToString:@"editor.text.letterSpacing"]) {
        return NO;
    }
    *value = self.letterSpacing;
    return YES;
}

- (NSString*)pluginHostActiveDocument:(KineticPluginHost*)host {
    (void)host;
    return self.document;
}

- (BOOL)pluginHost:(KineticPluginHost*)host replaceSelection:(NSString*)text {
    (void)host;
    self.document = [self.document stringByAppendingString:text];
    return YES;
}

@end

static void require(BOOL condition, NSString* message) {
    if (!condition) {
        NSLog(@"Plugin host test failed: %@", message);
        exit(1);
    }
}

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        require(argc == 2, @"plugin directory argument");
        TestPluginDelegate* delegate = [[TestPluginDelegate alloc] init];
        delegate.document = @"hello";
        KineticPluginHost* host = [[KineticPluginHost alloc] init];
        host.delegate = delegate;
        [host loadPluginsAtUrl:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]
                                      isDirectory:YES]];
        require(host.loadedPluginNames.count == 1, @"sample plugin loaded");
        require(delegate.letterSpacing == 1.25, @"plugin changed typography");
        require(host.commands.count == 2, @"plugin registered commands");
        require([host executeCommand:@"sample.increaseSpacing"], @"plugin command executed");
        require(delegate.letterSpacing == 2.0, @"command changed typography");
        [host emitEvent:@"document.activated"];
        require(delegate.letterSpacing == 3.0, @"plugin received editor event");
        require([host executeCommand:@"sample.appendMarker"], @"document command executed");
        require([delegate.document isEqualToString:@"hello!"], @"document API changed text");
        require(![host executeCommand:@"unknown.command"], @"unknown command rejected");
    }
    return 0;
}
