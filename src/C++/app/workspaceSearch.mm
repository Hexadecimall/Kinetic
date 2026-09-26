#import "workspaceSearch.h"

namespace {

constexpr NSUInteger kMaximumFileBytes = 1024 * 1024;
constexpr NSUInteger kMaximumFiles = 10000;
constexpr NSUInteger kMaximumMatchesPerFile = 40;
const unichar kNullCharacter = 0;

BOOL excludedDirectory(NSString* name) {
    static NSSet<NSString*>* excluded = [NSSet setWithArray:@[
        @"node_modules",
        @"target",
        @"build",
        @"dist",
        @".git",
        @".svn",
        @".hg",
    ]];
    return [excluded containsObject:name.lowercaseString];
}

NSString* relativePathForUrl(NSURL* url, NSURL* rootUrl) {
    NSString* rootPath = rootUrl.path;
    NSString* path = url.path;
    if ([path hasPrefix:[rootPath stringByAppendingString:@"/"]]) {
        return [path substringFromIndex:rootPath.length + 1];
    }
    return url.lastPathComponent;
}

NSDictionary* searchResult(NSURL* url, NSString* relativePath, NSUInteger line, NSUInteger column,
                           NSUInteger length, NSString* preview) {
    return @{
        @"url" : url,
        @"relativePath" : relativePath,
        @"line" : @(line),
        @"column" : @(column),
        @"length" : @(length),
        @"preview" : preview,
    };
}

} // namespace

NSArray<NSDictionary*>* kineticSearchText(NSString* contents, NSString* query, BOOL matchCase,
                                          NSUInteger maximumResults, BOOL* truncated) {
    if (truncated != nullptr) {
        *truncated = NO;
    }
    if (contents == nil || query.length == 0 || maximumResults == 0) {
        return @[];
    }
    NSMutableArray<NSDictionary*>* results = [NSMutableArray array];
    NSStringCompareOptions options = matchCase ? 0 : NSCaseInsensitiveSearch;
    __block NSUInteger lineNumber = 0;
    [contents enumerateLinesUsingBlock:^(NSString* line, BOOL* stop) {
      ++lineNumber;
      NSUInteger cursor = 0;
      while (cursor < line.length) {
          NSRange range = [line rangeOfString:query
                                      options:options
                                        range:NSMakeRange(cursor, line.length - cursor)];
          if (range.location == NSNotFound) {
              break;
          }
          NSString* preview =
              [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
          if (preview.length > 160) {
              preview = [[preview substringToIndex:160] stringByAppendingString:@"…"];
          }
          [results addObject:@{
              @"line" : @(lineNumber),
              @"column" : @(range.location + 1),
              @"length" : @(range.length),
              @"preview" : preview,
          }];
          if (results.count >= maximumResults) {
              if (truncated != nullptr) {
                  *truncated = YES;
              }
              *stop = YES;
              break;
          }
          cursor = NSMaxRange(range);
      }
    }];
    return results;
}

NSArray<NSDictionary*>* kineticSearchWorkspace(NSURL* rootUrl, NSString* query, BOOL matchCase,
                                               NSDictionary<NSString*, NSString*>* openDocuments,
                                               NSUInteger maximumResults, BOOL* truncated) {
    if (truncated != nullptr) {
        *truncated = NO;
    }
    if (rootUrl == nil || query.length == 0 || maximumResults == 0) {
        return @[];
    }

    NSFileManager* manager = NSFileManager.defaultManager;
    NSDirectoryEnumerator<NSURL*>* enumerator =
        [manager enumeratorAtURL:rootUrl
            includingPropertiesForKeys:@[
                NSURLIsDirectoryKey, NSURLIsRegularFileKey, NSURLIsSymbolicLinkKey, NSURLFileSizeKey
            ]
                               options:NSDirectoryEnumerationSkipsHiddenFiles |
                                       NSDirectoryEnumerationSkipsPackageDescendants
                          errorHandler:nil];
    NSMutableArray<NSDictionary*>* results = [NSMutableArray array];
    NSMutableDictionary<NSString*, NSString*>* normalizedOpenDocuments =
        [NSMutableDictionary dictionaryWithCapacity:openDocuments.count];
    for (NSString* path in openDocuments) {
        NSString* normalizedPath = [[NSURL fileURLWithPath:path] URLByResolvingSymlinksInPath].path;
        normalizedOpenDocuments[normalizedPath] = openDocuments[path];
    }
    NSStringCompareOptions options = matchCase ? 0 : NSCaseInsensitiveSearch;
    NSUInteger filesScanned = 0;
    for (NSURL* url in enumerator) {
        NSNumber* directory = nil;
        [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
        if (directory.boolValue) {
            if (excludedDirectory(url.lastPathComponent)) {
                [enumerator skipDescendants];
            }
            continue;
        }
        NSNumber* regularFile = nil;
        NSNumber* symbolicLink = nil;
        NSNumber* fileSize = nil;
        [url getResourceValue:&regularFile forKey:NSURLIsRegularFileKey error:nil];
        [url getResourceValue:&symbolicLink forKey:NSURLIsSymbolicLinkKey error:nil];
        [url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
        if (!regularFile.boolValue || symbolicLink.boolValue ||
            fileSize.unsignedLongLongValue > kMaximumFileBytes) {
            continue;
        }
        if (++filesScanned > kMaximumFiles) {
            if (truncated != nullptr) {
                *truncated = YES;
            }
            break;
        }

        NSString* contents = normalizedOpenDocuments[[url URLByResolvingSymlinksInPath].path];
        if (contents == nil) {
            NSData* bytes = [NSData dataWithContentsOfURL:url
                                                  options:NSDataReadingMappedIfSafe
                                                    error:nil];
            contents = [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
        }
        NSString* nullText = [NSString stringWithCharacters:&kNullCharacter length:1];
        if (contents == nil || [contents rangeOfString:nullText].location != NSNotFound) {
            continue;
        }
        NSString* path = relativePathForUrl(url, rootUrl);
        if ([url.lastPathComponent rangeOfString:query options:options].location != NSNotFound) {
            [results addObject:searchResult(url, path, 0, 0, query.length, @"File name match")];
            if (results.count >= maximumResults) {
                if (truncated != nullptr) {
                    *truncated = YES;
                }
                break;
            }
        }

        __block NSUInteger lineNumber = 0;
        __block NSUInteger matchesInFile = 0;
        [contents enumerateLinesUsingBlock:^(NSString* line, BOOL* stop) {
          ++lineNumber;
          NSRange match = [line rangeOfString:query options:options];
          if (match.location == NSNotFound) {
              return;
          }
          NSString* preview =
              [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
          if (preview.length > 160) {
              preview = [[preview substringToIndex:160] stringByAppendingString:@"…"];
          }
          [results addObject:searchResult(url, path, lineNumber, match.location + 1, match.length,
                                          preview)];
          if (++matchesInFile >= kMaximumMatchesPerFile || results.count >= maximumResults) {
              *stop = YES;
          }
        }];
        if (results.count >= maximumResults) {
            if (truncated != nullptr) {
                *truncated = YES;
            }
            break;
        }
    }
    [results sortUsingComparator:^NSComparisonResult(NSDictionary* left, NSDictionary* right) {
      NSComparisonResult pathOrder =
          [left[@"relativePath"] localizedCaseInsensitiveCompare:right[@"relativePath"]];
      if (pathOrder != NSOrderedSame) {
          return pathOrder;
      }
      return [left[@"line"] compare:right[@"line"]];
    }];
    return results;
}
