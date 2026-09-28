#pragma once
#import <AppKit/AppKit.h>

NSArray<NSDictionary*>* kineticSettingsRows(void);

@interface KineticSettingsPanel : NSView
@property(nonatomic, copy) double (^readNumber)(NSString* property);
@property(nonatomic, copy) BOOL (^writeNumber)(NSString* property, double value);
@property(nonatomic, copy) void (^applicationAction)(NSString* action);
@property(nonatomic, copy) NSString* applicationStatus;
@end
