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
        NSURL* userRootUrl = [KineticPluginHost userPluginRootUrl];
        require([userRootUrl.lastPathComponent isEqualToString:@".kinetic"],
                @"plugin root uses a dot-directory");
        require([userRootUrl.URLByDeletingLastPathComponent.path isEqualToString:NSHomeDirectory()],
                @"plugin root lives directly under the user home");
        NSURL* pluginDirectory = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]
                                             isDirectory:YES];
        NSURL* temporaryDirectory = [NSURL
            fileURLWithPath:[NSTemporaryDirectory()
                                stringByAppendingPathComponent:NSUUID.UUID.UUIDString]
               isDirectory:YES];
        require([NSFileManager.defaultManager createDirectoryAtURL:temporaryDirectory
                                        withIntermediateDirectories:NO
                                                         attributes:nil
                                                              error:nil], @"temporary config directory");
        NSURL* configurationUrl = [temporaryDirectory URLByAppendingPathComponent:@"config.toml"];
        TestPluginDelegate* delegate = [[TestPluginDelegate alloc] init];
        delegate.document = @"hello";
        KineticPluginHost* host = [[KineticPluginHost alloc] init];
        host.delegate = delegate;
        [host loadPluginsAtUrl:pluginDirectory configurationUrl:configurationUrl];
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

        NSString* disabled = @"[plugins]\ndisabledFiles = [\"kineticSamplePlugin.dylib\"]\n";
        require([disabled writeToURL:configurationUrl atomically:YES
                           encoding:NSUTF8StringEncoding error:nil], @"write disabled config");
        KineticPluginHost* disabledHost = [[KineticPluginHost alloc] init];
        disabledHost.delegate = delegate;
        [disabledHost loadPluginsAtUrl:pluginDirectory configurationUrl:configurationUrl];
        require(disabledHost.loadedPluginNames.count == 0, @"disabled library was not loaded");
        require(disabledHost.configurationError == nil, @"disabled config accepted");

        require([@"[plugins]\nenabled = false\n" writeToURL:configurationUrl atomically:YES
                                              encoding:NSUTF8StringEncoding error:nil],
                @"write globally disabled config");
        KineticPluginHost* globallyDisabledHost = [[KineticPluginHost alloc] init];
        globallyDisabledHost.delegate = delegate;
        [globallyDisabledHost loadPluginsAtUrl:pluginDirectory configurationUrl:configurationUrl];
        require(globallyDisabledHost.loadedPluginNames.count == 0, @"all plugins disabled");

        require([@"[plugins]\ndisabledFiles = [\"../bad.dylib\"]\n"
                    writeToURL:configurationUrl atomically:YES
                       encoding:NSUTF8StringEncoding error:nil], @"write invalid config");
        KineticPluginHost* invalidHost = [[KineticPluginHost alloc] init];
        invalidHost.delegate = delegate;
        [invalidHost loadPluginsAtUrl:pluginDirectory configurationUrl:configurationUrl];
        require(invalidHost.loadedPluginNames.count == 0, @"invalid config loads nothing");
        require(invalidHost.configurationError.length > 0, @"invalid config has visible error");
        [NSFileManager.defaultManager removeItemAtURL:temporaryDirectory error:nil];
    }
    return 0;
}
