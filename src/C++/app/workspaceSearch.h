#pragma once

#import <Foundation/Foundation.h>

NSArray<NSDictionary*>* kineticSearchText(NSString* contents, NSString* query, BOOL matchCase,
                                          NSUInteger maximumResults, BOOL* truncated);

NSArray<NSDictionary*>* kineticSearchWorkspace(NSURL* rootUrl, NSString* query, BOOL matchCase,
                                               NSDictionary<NSString*, NSString*>* openDocuments,
                                               NSUInteger maximumResults, BOOL* truncated);
