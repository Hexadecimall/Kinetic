#pragma once

#import <Foundation/Foundation.h>

NSArray<NSDictionary*>* kineticSearchWorkspace(NSURL* rootUrl, NSString* query, BOOL matchCase,
                                               NSDictionary<NSString*, NSString*>* openDocuments,
                                               NSUInteger maximumResults, BOOL* truncated);
