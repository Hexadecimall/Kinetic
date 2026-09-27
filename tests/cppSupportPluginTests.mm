#import <AppKit/AppKit.h>

#import "pluginHost.h"

@interface CppSupportDelegate : NSObject <KineticPluginHostDelegate>
@property(nonatomic, copy) NSString* source;
@property(nonatomic, copy) NSString* path;
@property(nonatomic) NSRange selection;
@property(nonatomic, copy) NSArray<NSDictionary<NSString*, id>*>* diagnostics;
@property(nonatomic, copy) NSString* definitionPath;
@property(nonatomic) NSUInteger definitionLine;
@end

@implementation CppSupportDelegate
- (BOOL)pluginHost:(KineticPluginHost*)host setNumber:(double)value property:(NSString*)property {
    (void)host;
    (void)value;
    (void)property;
    return NO;
}
- (BOOL)pluginHost:(KineticPluginHost*)host getNumber:(double*)value property:(NSString*)property {
    (void)host;
    (void)value;
    (void)property;
    return NO;
}
- (BOOL)pluginHost:(KineticPluginHost*)host
         setString:(NSString*)value
          property:(NSString*)property {
    (void)host;
    (void)value;
    (void)property;
    return NO;
}
- (NSString*)pluginHost:(KineticPluginHost*)host getString:(NSString*)property {
    (void)host;
    (void)property;
    return nil;
}
- (NSString*)pluginHostActiveDocument:(KineticPluginHost*)host {
    (void)host;
    return self.source;
}
- (NSString*)pluginHostActiveFilePath:(KineticPluginHost*)host {
    (void)host;
    return self.path;
}
- (NSString*)pluginHostWorkspacePath:(KineticPluginHost*)host {
    (void)host;
    return self.path.stringByDeletingLastPathComponent;
}
- (BOOL)pluginHost:(KineticPluginHost*)host replaceSelection:(NSString*)text {
    (void)host;
    (void)text;
    return NO;
}
- (BOOL)pluginHost:(KineticPluginHost*)host getSelection:(NSRange*)selection {
    (void)host;
    *selection = self.selection;
    return YES;
}
- (BOOL)pluginHost:(KineticPluginHost*)host setSelection:(NSRange)selection {
    (void)host;
    self.selection = selection;
    return YES;
}
- (BOOL)pluginHost:(KineticPluginHost*)host replaceRange:(NSRange)range withString:(NSString*)text {
    (void)host;
    (void)range;
    (void)text;
    return NO;
}
- (void)pluginHost:(KineticPluginHost*)host
    publishDiagnostics:(NSArray<NSDictionary<NSString*, id>*>*)diagnostics
               forPath:(NSString*)path {
    (void)host;
    if ([path.stringByResolvingSymlinksInPath
            isEqualToString:self.path.stringByResolvingSymlinksInPath]) {
        self.diagnostics = diagnostics;
    }
}
- (void)pluginHost:(KineticPluginHost*)host
    openLocationAtPath:(NSString*)path
                  line:(NSUInteger)line
                column:(NSUInteger)column {
    (void)host;
    (void)column;
    self.definitionPath = path;
    self.definitionLine = line;
}
@end

static void require(BOOL condition, NSString* message) {
    if (!condition) {
        NSLog(@"C/C++ Support test failed: %@", message);
        exit(1);
    }
}

static BOOL waitUntil(BOOL (^condition)(void)) {
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:12.0];
    while (!condition() && [deadline timeIntervalSinceNow] > 0.0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return condition();
}

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        require(argc == 2, @"plugin directory argument");
        NSString* root =
            [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        require([NSFileManager.defaultManager createDirectoryAtPath:root
                                        withIntermediateDirectories:YES
                                                         attributes:nil
                                                              error:nil],
                @"temporary workspace");
        CppSupportDelegate* delegate = [[CppSupportDelegate alloc] init];
        delegate.path = [root stringByAppendingPathComponent:@"main.cpp"];
        delegate.source = @"int main() { return unknownSymbol; }\n";
        require([delegate.source writeToFile:delegate.path
                                  atomically:YES
                                    encoding:NSUTF8StringEncoding
                                       error:nil],
                @"source file");
        KineticPluginHost* host = [[KineticPluginHost alloc] init];
        host.delegate = delegate;
        [host loadPluginsAtUrl:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]
              configurationUrl:
                  [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"config.toml"]]];
        require([host.loadedPluginNames containsObject:@"C/C++ Support"], @"plugin loaded");
        NSArray* syntax = [host syntaxTokensForLines:@[ @"constexpr int value = 42;" ]
                                            fileName:@"main.cpp"];
        require(syntax.count == 1 && [syntax[0] count] >= 3, @"plugin syntax tokens");
        [host emitEvent:@"document.activated"];
        require(waitUntil(^BOOL {
                  for (NSDictionary* diagnostic in delegate.diagnostics) {
                      if ([diagnostic[@"severity"] integerValue] == 1 &&
                          [diagnostic[@"message"] containsString:@"unknownSymbol"]) {
                          return YES;
                      }
                  }
                  return NO;
                }),
                @"clangd delivered an inline error");

        delegate.source = @"int answer() { return 42; }\nint main() { return answer(); }\n";
        require([delegate.source writeToFile:delegate.path
                                  atomically:YES
                                    encoding:NSUTF8StringEncoding
                                       error:nil],
                @"updated source");
        delegate.selection = [delegate.source rangeOfString:@"answer" options:NSBackwardsSearch];
        delegate.selection = NSMakeRange(delegate.selection.location, 0);
        [host emitEvent:@"document.changed"];
        require([host executeCommand:@"kinetic.cpp.goToDefinition"], @"definition command");
        require(waitUntil(^BOOL {
                  return delegate.definitionLine == 1;
                }),
                @"clangd definition result");
        require([delegate.definitionPath.stringByResolvingSymlinksInPath
                    isEqualToString:delegate.path.stringByResolvingSymlinksInPath],
                @"definition path");
        delegate.source = @"int answer() { return 42; }\nint main() { ans\n";
        delegate.selection = NSMakeRange(
            [delegate.source rangeOfString:@"ans" options:NSBackwardsSearch].location + 3, 0);
        [host emitEvent:@"document.changed"];
        require([host hasCompletionProviderForFileName:@"main.cpp"],
                @"clangd completion provider registered");
        require(waitUntil(^BOOL {
                  NSArray* items = [host completionItemsForPrefix:@"ans" fileName:@"main.cpp"];
                  for (NSDictionary* item in items) {
                      if ([item[@"insertText"] isEqualToString:@"answer"]) {
                          return YES;
                      }
                  }
                  return NO;
                }),
                @"clangd returned answer completion");
        NSString* headerPath = [root stringByAppendingPathComponent:@"main.hpp"];
        require([@"int answer();\n" writeToFile:headerPath
                                     atomically:YES
                                       encoding:NSUTF8StringEncoding
                                          error:nil],
                @"header file");
        delegate.definitionLine = 0;
        require([host executeCommand:@"kinetic.cpp.switchHeaderSource"], @"header command");
        require(waitUntil(^BOOL {
                  return delegate.definitionLine == 1;
                }),
                @"header navigation");
        require([delegate.definitionPath.stringByResolvingSymlinksInPath
                    isEqualToString:headerPath.stringByResolvingSymlinksInPath],
                @"header path");
        require([host hasFormatterForFileName:@"main.cpp"], @"clang-format registered");
        NSString* formatted = [host formatDocument:@"int main(){return 0;}\n" fileName:@"main.cpp"];
        require([formatted containsString:@"int main()"], @"clang-format output");
        host = nil;
        [NSFileManager.defaultManager removeItemAtPath:root error:nil];
    }
    return 0;
}
