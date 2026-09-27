#pragma once

#import <Foundation/Foundation.h>

@interface KineticStructureEdit : NSObject
@property(nonatomic, readonly) NSRange range;
@property(nonatomic, readonly, copy) NSString* replacement;
@property(nonatomic, readonly) NSUInteger anchorOffset;
@property(nonatomic, readonly) NSUInteger caretOffset;
- (instancetype)initWithRange:(NSRange)range
                  replacement:(NSString*)replacement
                 anchorOffset:(NSUInteger)anchorOffset
                  caretOffset:(NSUInteger)caretOffset;
@end

KineticStructureEdit* kineticNewlineEdit(NSString* text, NSRange selection, NSString* fileName,
                                         NSUInteger tabWidth, BOOL autoIndent);
KineticStructureEdit* kineticNewlineEditWithTabs(NSString* text, NSRange selection,
                                                 NSString* fileName, NSUInteger tabWidth,
                                                 BOOL autoIndent, BOOL insertTabs);
KineticStructureEdit* kineticTabEdit(NSString* text, NSRange selection, NSUInteger tabWidth,
                                     BOOL outdent);
KineticStructureEdit* kineticTabEditWithTabs(NSString* text, NSRange selection, NSUInteger tabWidth,
                                             BOOL outdent, BOOL insertTabs);
KineticStructureEdit* kineticIndentBackspaceEdit(NSString* text, NSUInteger caretIndex,
                                                 NSUInteger tabWidth);
NSUInteger kineticIndentNavigationIndex(NSString* text, NSUInteger caretIndex, NSUInteger tabWidth,
                                        BOOL forward);
NSUInteger kineticIndentSnapIndex(NSString* text, NSUInteger caretIndex, NSUInteger tabWidth);
KineticStructureEdit* kineticTypedStructureEdit(NSString* text, NSRange selection,
                                                NSString* character, NSUInteger tabWidth,
                                                BOOL autoPairs);
KineticStructureEdit* kineticPairedBackspaceEdit(NSString* text, NSUInteger caretIndex,
                                                 BOOL autoPairs);
