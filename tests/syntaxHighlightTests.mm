#import <Foundation/Foundation.h>

#import "syntaxHighlight.h"

static void require(BOOL condition, NSString* message) {
    if (!condition) {
        NSLog(@"Syntax test failed: %@", message);
        exit(1);
    }
}

static BOOL hasKind(NSArray<NSDictionary<NSString*, id>*>* tokens, NSRange range,
                    KineticSyntaxKind kind) {
    for (NSDictionary<NSString*, id>* token in tokens) {
        if (NSEqualRanges([token[@"range"] rangeValue], range) &&
            [token[@"kind"] integerValue] == kind) {
            return YES;
        }
    }
    return NO;
}

int main() {
    @autoreleasepool {
        NSArray* lines = @[ @"#!/bin/bash", @"if [ -n \"$HOME\" ]; then # check", @"echo ${NAME} 42" ];
        auto tokens = kineticSyntaxTokens(lines, @"script");
        require(tokens.count == 3, @"extensionless shell shebang");
        require(hasKind(tokens[0], NSMakeRange(0, 11), KineticSyntaxKindDirective),
                @"shell shebang");
        require(hasKind(tokens[1], NSMakeRange(0, 2), KineticSyntaxKindKeyword), @"shell keyword");
        require(hasKind(tokens[1], NSMakeRange(8, 7), KineticSyntaxKindString),
                @"quoted shell variable stays a string");
        require(hasKind(tokens[2], NSMakeRange(5, 7), KineticSyntaxKindVariable),
                @"shell parameter expansion");
        require(hasKind(tokens[2], NSMakeRange(0, 4), KineticSyntaxKindFunction),
                @"shell builtin");

        tokens = kineticSyntaxTokens(@[ @"/* open", @"still comment */ int value = 42;" ],
                                     @"sample.cpp");
        require(hasKind(tokens[0], NSMakeRange(0, 7), KineticSyntaxKindComment),
                @"block comment begins");
        require(hasKind(tokens[1], NSMakeRange(0, 16), KineticSyntaxKindComment),
                @"block comment ends on next line");
        require(hasKind(tokens[1], NSMakeRange(17, 3), KineticSyntaxKindKeyword),
                @"code resumes after comment");

        tokens = kineticSyntaxTokens(@[ @"message = \"not // a comment\"", @"// real comment" ],
                                     @"sample.ts");
        require(hasKind(tokens[0], NSMakeRange(10, 18), KineticSyntaxKindString),
                @"comment marker inside string");
        require(hasKind(tokens[1], NSMakeRange(0, 15), KineticSyntaxKindComment),
                @"line comment");

        tokens = kineticSyntaxTokens(@[ @"\"name\": true, \"count\": 12" ], @"data.json");
        require(hasKind(tokens[0], NSMakeRange(0, 6), KineticSyntaxKindKey), @"JSON key");
        require(hasKind(tokens[0], NSMakeRange(8, 4), KineticSyntaxKindConstant), @"JSON boolean");
        require(hasKind(tokens[0], NSMakeRange(23, 2), KineticSyntaxKindNumber), @"JSON number");

        tokens = kineticSyntaxTokens(@[ @"'''hello", @"world'''", @"def run():" ], @"app.py");
        require(hasKind(tokens[0], NSMakeRange(0, 8), KineticSyntaxKindString),
                @"Python triple string begins");
        require(hasKind(tokens[1], NSMakeRange(0, 8), KineticSyntaxKindString),
                @"Python triple string ends");
        require(hasKind(tokens[2], NSMakeRange(0, 3), KineticSyntaxKindKeyword),
                @"Python keyword after string");

        tokens = kineticSyntaxTokens(@[ @"pub fn greet() -> bool { true }" ], @"main.rs");
        require(hasKind(tokens[0], NSMakeRange(0, 3), KineticSyntaxKindKeyword), @"Rust keyword");
        require(hasKind(tokens[0], NSMakeRange(7, 5), KineticSyntaxKindFunction), @"function name");

        tokens = kineticSyntaxTokens(@[ @"[editor]", @"syntaxHighlighting = true # enabled" ],
                                     @"kinetic.toml");
        require(hasKind(tokens[1], NSMakeRange(0, 18), KineticSyntaxKindKey), @"TOML key");
        require(hasKind(tokens[1], NSMakeRange(21, 4), KineticSyntaxKindConstant), @"TOML value");

        tokens = kineticSyntaxTokens(@[ @"<!-- first", @"last --> <main title=\"Hi\">" ],
                                     @"index.html");
        require(hasKind(tokens[0], NSMakeRange(0, 10), KineticSyntaxKindComment),
                @"HTML comment begins");
        require(hasKind(tokens[1], NSMakeRange(0, 8), KineticSyntaxKindComment),
                @"HTML comment ends");
        require(hasKind(tokens[1], NSMakeRange(9, 5), KineticSyntaxKindKeyword), @"HTML tag");

        require(kineticSyntaxTokens(@[ @"some plain text" ], @"notes.txt").count == 0,
                @"unknown file remains plain text");
    }
    return 0;
}
