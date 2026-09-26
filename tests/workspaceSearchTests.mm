#import <Foundation/Foundation.h>

#include "workspaceSearch.h"

static void require(BOOL condition, NSString* message) {
    if (!condition) {
        NSLog(@"Search test failed: %@", message);
        exit(1);
    }
}

int main() {
    @autoreleasepool {
        NSFileManager* manager = NSFileManager.defaultManager;
        NSURL* rootUrl =
            [NSURL fileURLWithPath:[NSTemporaryDirectory()
                                       stringByAppendingPathComponent:
                                           [@"kineticSearch-"
                                               stringByAppendingString:NSUUID.UUID.UUIDString]]
                       isDirectory:YES];
        NSError* error = nil;
        require([manager createDirectoryAtURL:rootUrl
                    withIntermediateDirectories:NO
                                     attributes:nil
                                          error:&error],
                @"create fixture folder");
        @try {
            NSURL* sourceUrl = [rootUrl URLByAppendingPathComponent:@"Source.txt"];
            NSURL* hiddenUrl = [rootUrl URLByAppendingPathComponent:@".hidden.txt"];
            NSURL* binaryUrl = [rootUrl URLByAppendingPathComponent:@"binary.dat"];
            require([@"first line\nHello Kinetic\nlast line" writeToURL:sourceUrl
                                                             atomically:YES
                                                               encoding:NSUTF8StringEncoding
                                                                  error:&error],
                    @"write source");
            require([@"Hello hidden" writeToURL:hiddenUrl
                                     atomically:YES
                                       encoding:NSUTF8StringEncoding
                                          error:&error],
                    @"write hidden");
            const unsigned char binaryBytes[] = {'H', 'e', 'l', 'l', 'o', 0, 'x'};
            require([[NSData dataWithBytes:binaryBytes
                                    length:sizeof(binaryBytes)] writeToURL:binaryUrl
                                                                atomically:YES],
                    @"write binary");

            BOOL truncated = NO;
            NSArray<NSDictionary*>* results =
                kineticSearchWorkspace(rootUrl, @"hello", NO, @{}, 10, &truncated);
            require(results.count == 1 && !truncated, @"case-insensitive text match only");
            require([results[0][@"line"] unsignedIntegerValue] == 2 &&
                        [results[0][@"column"] unsignedIntegerValue] == 1,
                    @"result position");
            require(kineticSearchWorkspace(rootUrl, @"hello", YES, @{}, 10, nullptr).count == 0,
                    @"match case");
            require(kineticSearchWorkspace(rootUrl, @"source", NO, @{}, 10, nullptr).count == 1,
                    @"filename match");
            results = kineticSearchWorkspace(rootUrl, @"unsaved", NO,
                                             @{sourceUrl.path : @"unsaved work"}, 10, nullptr);
            require(results.count == 1, @"searches unsaved open document text");
            results = kineticSearchWorkspace(rootUrl, @"line", NO, @{}, 1, &truncated);
            require(results.count == 1 && truncated, @"result cap");
        } @finally {
            [manager removeItemAtURL:rootUrl error:nil];
        }
    }
    return 0;
}
