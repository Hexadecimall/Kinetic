#pragma once

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, KineticSyntaxKind) {
    KineticSyntaxKindKeyword,
    KineticSyntaxKindString,
    KineticSyntaxKindComment,
    KineticSyntaxKindNumber,
    KineticSyntaxKindConstant,
    KineticSyntaxKindType,
    KineticSyntaxKindFunction,
    KineticSyntaxKindVariable,
    KineticSyntaxKindKey,
    KineticSyntaxKindDirective,
};

// Each token contains an NSValue range and NSNumber kind. Ranges use NSString UTF-16 indexes.
NSArray<NSArray<NSDictionary<NSString*, id>*>*>* kineticSyntaxTokens(NSArray<NSString*>* lines,
                                                                     NSString* fileName);
