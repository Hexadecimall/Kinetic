#import "syntaxHighlight.h"

namespace {

enum class SyntaxLanguage {
    plain,
    brace,
    python,
    shell,
    json,
    jsonWithComments,
    config,
    markup,
    css,
};

enum class MultilineState {
    none,
    blockComment,
    tripleSingle,
    tripleDouble,
    markupComment,
};

bool isWordStart(unichar character) {
    return (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') ||
           character == '_';
}

bool isWordPart(unichar character) {
    return isWordStart(character) || (character >= '0' && character <= '9');
}

bool isDigit(unichar character) {
    return character >= '0' && character <= '9';
}

void addToken(NSMutableArray<NSDictionary<NSString*, id>*>* tokens, NSUInteger start,
              NSUInteger end, KineticSyntaxKind kind) {
    if (end > start) {
        [tokens addObject:@{
            @"range" : [NSValue valueWithRange:NSMakeRange(start, end - start)],
            @"kind" : @(kind),
        }];
    }
}

bool matches(NSString* text, NSUInteger index, NSString* candidate) {
    return index + candidate.length <= text.length &&
           [[text substringWithRange:NSMakeRange(index, candidate.length)]
               isEqualToString:candidate];
}

NSSet<NSString*>* wordSet(NSString* words) {
    return [NSSet setWithArray:[words componentsSeparatedByString:@" "]];
}

SyntaxLanguage languageForFile(NSString* fileName, NSString* firstLine) {
    NSString* name = fileName.lowercaseString ?: @"";
    NSString* extension = name.pathExtension;
    if ([wordSet(@"sh bash zsh fish ksh command") containsObject:extension] ||
        [wordSet(@".bashrc .zshrc .profile .bash_profile .zprofile") containsObject:name]) {
        return SyntaxLanguage::shell;
    }
    if ([wordSet(@"py pyi") containsObject:extension]) {
        return SyntaxLanguage::python;
    }
    if ([wordSet(@"c h cc cpp cxx hpp hh m mm rs go java js jsx ts tsx swift zig cs kt kts")
            containsObject:extension]) {
        return SyntaxLanguage::brace;
    }
    if ([extension isEqualToString:@"json"]) {
        return SyntaxLanguage::json;
    }
    if ([extension isEqualToString:@"jsonc"]) {
        return SyntaxLanguage::jsonWithComments;
    }
    if ([wordSet(@"toml yaml yml ini cfg") containsObject:extension]) {
        return SyntaxLanguage::config;
    }
    if ([wordSet(@"html htm xml svg") containsObject:extension]) {
        return SyntaxLanguage::markup;
    }
    if ([wordSet(@"css scss") containsObject:extension]) {
        return SyntaxLanguage::css;
    }
    if ([firstLine hasPrefix:@"#!"]) {
        NSString* lower = firstLine.lowercaseString;
        if ([lower containsString:@"python"]) {
            return SyntaxLanguage::python;
        }
        if ([lower containsString:@"sh"] || [lower containsString:@"bash"] ||
            [lower containsString:@"zsh"] || [lower containsString:@"fish"]) {
            return SyntaxLanguage::shell;
        }
    }
    return SyntaxLanguage::plain;
}

NSSet<NSString*>* keywordsForLanguage(SyntaxLanguage language, NSString* fileName) {
    static NSSet<NSString*>* commonKeywords;
    static NSSet<NSString*>* shellKeywords;
    static NSSet<NSString*>* pythonKeywords;
    static NSSet<NSString*>* rustKeywords;
    static NSSet<NSString*>* goKeywords;
    static NSSet<NSString*>* swiftKeywords;
    static NSSet<NSString*>* javaKeywords;
    static NSSet<NSString*>* javascriptKeywords;
    static NSSet<NSString*>* kotlinKeywords;
    static NSSet<NSString*>* zigKeywords;
    static NSSet<NSString*>* csharpKeywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      commonKeywords =
          wordSet(@"if else for while do switch case default break continue return "
                   "try catch finally throw class struct enum union interface "
                   "public private protected static const let var function func fn "
                   "import export from as new this super extends implements "
                   "typedef using namespace template typename auto void int long short "
                   "float double char bool unsigned signed sizeof nullptr async await");
      shellKeywords = wordSet(@"if then else elif fi for in do done while until case esac "
                               "function select time coproc export local readonly declare typeset "
                               "source alias unset return break continue trap set shift");
      pythonKeywords = wordSet(@"and as assert async await break class continue def del elif else "
                                "except finally for from global if import in is lambda nonlocal "
                                "not or pass raise return try while with yield match case self");
      rustKeywords = wordSet(@"as async await const crate dyn enum extern fn for if impl in let "
                              "loop match mod move mut pub ref return self Self static struct "
                              "super trait type unsafe use where while break continue");
      goKeywords = wordSet(@"break case chan const continue default defer else fallthrough for "
                            "func go goto if import interface map package range return select "
                            "struct switch type var");
      swiftKeywords = wordSet(@"associatedtype class deinit enum extension func import init "
                               "inout internal let open operator private protocol public "
                               "rethrows static struct subscript typealias var break case catch "
                               "continue default defer do else fallthrough for guard if in "
                               "repeat return switch throw throws try where while as is");
      javaKeywords = wordSet(@"abstract assert boolean byte case catch char class const continue "
                              "default do double else enum extends final finally float for if "
                              "implements import instanceof int interface long native new "
                              "package private protected public return short static strictfp "
                              "super switch synchronized this throw throws transient try void "
                              "volatile while record sealed permits");
      javascriptKeywords = wordSet(@"async await break case catch class const continue debugger "
                                    "default delete do else export extends finally for from "
                                    "function if import in instanceof let new of return static "
                                    "super switch this throw try typeof var void while yield "
                                    "interface type implements namespace declare readonly keyof");
      kotlinKeywords = wordSet(@"as break class continue do else false for fun if in interface "
                                "is null object package return super this throw true try typealias "
                                "typeof val var when while by constructor delegate dynamic field "
                                "file finally get import init param property receiver set value "
                                "where actual abstract annotation companion const crossinline data "
                                "enum expect external final infix inline inner internal lateinit "
                                "noinline open operator out override private protected public "
                                "reified sealed suspend tailrec vararg");
      zigKeywords = wordSet(@"align allowzero and anyframe anytype asm async await break catch "
                             "comptime const continue defer else enum errdefer error export "
                             "extern fn for if inline noalias noinline nosuspend opaque or "
                             "orelse packed pub resume return linksection struct suspend "
                             "switch test threadlocal try union unreachable usingnamespace "
                             "var volatile while");
      csharpKeywords = wordSet(@"abstract as async await base bool break byte case catch char "
                                "checked class const continue decimal default delegate do double "
                                "else enum event explicit extern false finally fixed float for "
                                "foreach goto if implicit in int interface internal is lock long "
                                "namespace new null object operator out override params private "
                                "protected public readonly ref return sbyte sealed short sizeof "
                                "stackalloc static string struct switch this throw true try "
                                "typeof uint ulong unchecked unsafe ushort using virtual void "
                                "volatile while yield record var");
    });
    if (language == SyntaxLanguage::shell) {
        return shellKeywords;
    }
    if (language == SyntaxLanguage::python) {
        return pythonKeywords;
    }
    NSString* extension = fileName.lowercaseString.pathExtension;
    if ([extension isEqualToString:@"rs"]) {
        return rustKeywords;
    }
    if ([extension isEqualToString:@"go"]) {
        return goKeywords;
    }
    if ([extension isEqualToString:@"swift"]) {
        return swiftKeywords;
    }
    if ([extension isEqualToString:@"java"]) {
        return javaKeywords;
    }
    if ([extension isEqualToString:@"kt"] || [extension isEqualToString:@"kts"]) {
        return kotlinKeywords;
    }
    if ([extension isEqualToString:@"zig"]) {
        return zigKeywords;
    }
    if ([extension isEqualToString:@"cs"]) {
        return csharpKeywords;
    }
    if ([wordSet(@"js jsx ts tsx") containsObject:extension]) {
        return javascriptKeywords;
    }
    return commonKeywords;
}

NSUInteger scanQuoted(NSString* line, NSUInteger start, unichar quote) {
    NSUInteger index = start + 1;
    while (index < line.length) {
        unichar character = [line characterAtIndex:index];
        if (character == '\\' && index + 1 < line.length) {
            index += 2;
        } else if (character == quote) {
            return index + 1;
        } else {
            ++index;
        }
    }
    return index;
}

void scanLine(NSString* line, SyntaxLanguage language, NSSet<NSString*>* keywords,
              MultilineState& state, NSMutableArray<NSDictionary<NSString*, id>*>* tokens) {
    static NSSet<NSString*>* constants;
    static NSSet<NSString*>* shellBuiltins;
    static NSSet<NSString*>* types;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      constants = wordSet(@"true false null nil None True False undefined NaN self Self");
      shellBuiltins = wordSet(@"echo printf cd pwd read test exec eval exit source builtin "
                               "command dirs pushd popd wait jobs fg bg kill umask ulimit");
      types = wordSet(@"String NSString Int UInt Bool Float Double str bytes list dict "
                       "tuple set object size_t uint8_t uint32_t uint64_t usize i32 u32 "
                       "i64 u64 f32 f64 error any never");
    });
    NSUInteger index = 0;
    while (index < line.length) {
        NSUInteger start = index;
        if (state != MultilineState::none) {
            NSString* endMarker =
                state == MultilineState::blockComment
                    ? @"*/"
                    : (state == MultilineState::markupComment
                           ? @"-->"
                           : (state == MultilineState::tripleSingle ? @"'''" : @"\"\"\""));
            NSRange endRange = [line rangeOfString:endMarker
                                           options:0
                                             range:NSMakeRange(index, line.length - index)];
            index = endRange.location == NSNotFound ? line.length : NSMaxRange(endRange);
            addToken(tokens, start, index,
                     state == MultilineState::blockComment || state == MultilineState::markupComment
                         ? KineticSyntaxKindComment
                         : KineticSyntaxKindString);
            if (endRange.location != NSNotFound) {
                state = MultilineState::none;
            }
            continue;
        }

        unichar character = [line characterAtIndex:index];
        if (language == SyntaxLanguage::markup) {
            if (matches(line, index, @"<!--")) {
                NSRange endRange =
                    [line rangeOfString:@"-->"
                                options:0
                                  range:NSMakeRange(index + 4, line.length - index - 4)];
                index = endRange.location == NSNotFound ? line.length : NSMaxRange(endRange);
                state = endRange.location == NSNotFound ? MultilineState::markupComment
                                                        : MultilineState::none;
                addToken(tokens, start, index, KineticSyntaxKindComment);
                continue;
            }
            if (character == '<') {
                ++index;
                if (index < line.length && [line characterAtIndex:index] == '/') {
                    ++index;
                }
                while (index < line.length && (isWordPart([line characterAtIndex:index]) ||
                                               [line characterAtIndex:index] == '-')) {
                    ++index;
                }
                addToken(tokens, start, index, KineticSyntaxKindKeyword);
                continue;
            }
            if (character != '"' && character != '\'') {
                ++index;
                continue;
            }
        }

        if (matches(line, index, @"/*") &&
            (language == SyntaxLanguage::brace || language == SyntaxLanguage::jsonWithComments ||
             language == SyntaxLanguage::css)) {
            NSRange endRange = [line rangeOfString:@"*/"
                                           options:0
                                             range:NSMakeRange(index + 2, line.length - index - 2)];
            index = endRange.location == NSNotFound ? line.length : NSMaxRange(endRange);
            state = endRange.location == NSNotFound ? MultilineState::blockComment
                                                    : MultilineState::none;
            addToken(tokens, start, index, KineticSyntaxKindComment);
            continue;
        }
        if (matches(line, index, @"//") &&
            (language == SyntaxLanguage::brace || language == SyntaxLanguage::jsonWithComments ||
             language == SyntaxLanguage::css)) {
            addToken(tokens, index, line.length, KineticSyntaxKindComment);
            break;
        }
        if (character == '#' &&
            (language == SyntaxLanguage::shell || language == SyntaxLanguage::python ||
             language == SyntaxLanguage::config)) {
            addToken(tokens, index, line.length,
                     index == 0 && matches(line, index, @"#!") ? KineticSyntaxKindDirective
                                                               : KineticSyntaxKindComment);
            break;
        }
        if (character == '#' && language == SyntaxLanguage::brace &&
            [[line substringToIndex:index]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
                    .length == 0) {
            addToken(tokens, index, line.length, KineticSyntaxKindDirective);
            break;
        }
        if (language == SyntaxLanguage::python &&
            (matches(line, index, @"'''") || matches(line, index, @"\"\"\""))) {
            NSString* marker = [line characterAtIndex:index] == '\'' ? @"'''" : @"\"\"\"";
            NSRange endRange = [line rangeOfString:marker
                                           options:0
                                             range:NSMakeRange(index + 3, line.length - index - 3)];
            index = endRange.location == NSNotFound ? line.length : NSMaxRange(endRange);
            state = endRange.location == NSNotFound
                        ? ([marker isEqualToString:@"'''"] ? MultilineState::tripleSingle
                                                           : MultilineState::tripleDouble)
                        : MultilineState::none;
            addToken(tokens, start, index, KineticSyntaxKindString);
            continue;
        }
        if (character == '"' || character == '\'' ||
            (character == '`' &&
             (language == SyntaxLanguage::shell || language == SyntaxLanguage::brace))) {
            index = scanQuoted(line, index, character);
            NSUInteger next = index;
            while (next < line.length && [line characterAtIndex:next] == ' ') {
                ++next;
            }
            BOOL isKey =
                (language == SyntaxLanguage::json || language == SyntaxLanguage::jsonWithComments ||
                 language == SyntaxLanguage::config) &&
                next < line.length &&
                ([line characterAtIndex:next] == ':' ||
                 (language == SyntaxLanguage::config && [line characterAtIndex:next] == '='));
            addToken(tokens, start, index, isKey ? KineticSyntaxKindKey : KineticSyntaxKindString);
            continue;
        }
        if (language == SyntaxLanguage::shell && character == '$') {
            ++index;
            if (index < line.length && [line characterAtIndex:index] == '{') {
                ++index;
                while (index < line.length && [line characterAtIndex:index] != '}') {
                    ++index;
                }
                index += index < line.length ? 1 : 0;
            } else {
                while (index < line.length && isWordPart([line characterAtIndex:index])) {
                    ++index;
                }
                if (index == start + 1 && index < line.length) {
                    ++index;
                }
            }
            addToken(tokens, start, index, KineticSyntaxKindVariable);
            continue;
        }
        if (isDigit(character) && (index == 0 || !isWordPart([line characterAtIndex:index - 1]))) {
            ++index;
            while (index < line.length) {
                unichar next = [line characterAtIndex:index];
                if (!isWordPart(next) && next != '.' && next != '_') {
                    break;
                }
                ++index;
            }
            addToken(tokens, start, index, KineticSyntaxKindNumber);
            continue;
        }
        if (isWordStart(character)) {
            ++index;
            while (index < line.length && isWordPart([line characterAtIndex:index])) {
                ++index;
            }
            NSString* word = [line substringWithRange:NSMakeRange(start, index - start)];
            if ([keywords containsObject:word]) {
                addToken(tokens, start, index, KineticSyntaxKindKeyword);
            } else if ([constants containsObject:word]) {
                addToken(tokens, start, index, KineticSyntaxKindConstant);
            } else if ([types containsObject:word]) {
                addToken(tokens, start, index, KineticSyntaxKindType);
            } else if (language == SyntaxLanguage::shell && [shellBuiltins containsObject:word]) {
                addToken(tokens, start, index, KineticSyntaxKindFunction);
            } else {
                NSUInteger next = index;
                while (next < line.length && [line characterAtIndex:next] == ' ') {
                    ++next;
                }
                if (language == SyntaxLanguage::config && next < line.length &&
                    ([line characterAtIndex:next] == '=' || [line characterAtIndex:next] == ':')) {
                    addToken(tokens, start, index, KineticSyntaxKindKey);
                } else if (language == SyntaxLanguage::shell && next < line.length &&
                           [line characterAtIndex:next] == '=') {
                    addToken(tokens, start, index, KineticSyntaxKindVariable);
                } else if (language == SyntaxLanguage::json && next < line.length &&
                           [line characterAtIndex:next] == ':') {
                    addToken(tokens, start, index, KineticSyntaxKindKey);
                } else if (next < line.length && [line characterAtIndex:next] == '(' &&
                           language != SyntaxLanguage::json && language != SyntaxLanguage::config) {
                    addToken(tokens, start, index, KineticSyntaxKindFunction);
                }
            }
            continue;
        }
        ++index;
    }
}

} // namespace

NSArray<NSArray<NSDictionary<NSString*, id>*>*>* kineticSyntaxTokens(NSArray<NSString*>* lines,
                                                                     NSString* fileName) {
    if (lines.count == 0) {
        return @[];
    }
    SyntaxLanguage language = languageForFile(fileName, lines.firstObject);
    if (language == SyntaxLanguage::plain) {
        return @[];
    }
    NSSet<NSString*>* keywords = keywordsForLanguage(language, fileName);
    MultilineState state = MultilineState::none;
    NSMutableArray<NSArray<NSDictionary<NSString*, id>*>*>* result =
        [NSMutableArray arrayWithCapacity:lines.count];
    for (NSString* line in lines) {
        NSMutableArray<NSDictionary<NSString*, id>*>* tokens = [NSMutableArray array];
        scanLine(line, language, keywords, state, tokens);
        [result addObject:tokens];
    }
    return result;
}
