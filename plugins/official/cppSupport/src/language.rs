use crate::SyntaxToken;

const KEYWORDS: &str = "alignas alignof asm auto break case catch class concept const consteval constexpr constinit const_cast continue co_await co_return co_yield decltype default delete do dynamic_cast else enum explicit export extern false for friend goto if import inline mutable namespace new noexcept nullptr operator private protected public register reinterpret_cast requires return sizeof static static_assert static_cast struct switch template this thread_local throw true try typedef typeid typename union using virtual volatile while";
const TYPES: &str = "bool char char8_t char16_t char32_t double float int long short signed unsigned void wchar_t size_t ptrdiff_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t";

fn wordIn(word: &str, choices: &str) -> bool {
    choices
        .split_ascii_whitespace()
        .any(|candidate| candidate == word)
}

fn append(
    line: &str,
    output: &mut [SyntaxToken],
    count: &mut usize,
    start: usize,
    end: usize,
    kind: u32,
) {
    if end <= start || *count >= output.len() {
        return;
    }
    let startUtf16 = line[..start].encode_utf16().count();
    let lengthUtf16 = line[start..end].encode_utf16().count();
    if let (Ok(startUtf16), Ok(lengthUtf16)) =
        (u32::try_from(startUtf16), u32::try_from(lengthUtf16))
    {
        output[*count] = SyntaxToken {
            startUtf16,
            lengthUtf16,
            kind,
        };
        *count += 1;
    }
}

pub fn tokens(line: &str, state: &mut u32, output: &mut [SyntaxToken]) -> usize {
    let bytes = line.as_bytes();
    let mut index = 0;
    let mut count = 0;
    if *state == 0 && line.trim_start().starts_with('#') {
        let start = line.len() - line.trim_start().len();
        append(line, output, &mut count, start, line.len(), 9);
        return count;
    }
    while index < bytes.len() {
        let start = index;
        if *state == 1 {
            if let Some(end) = line[index..].find("*/") {
                index += end + 2;
                *state = 0;
            } else {
                index = bytes.len();
            }
            append(line, output, &mut count, start, index, 2);
            continue;
        }
        if bytes[index..].starts_with(b"//") {
            append(line, output, &mut count, index, bytes.len(), 2);
            break;
        }
        if bytes[index..].starts_with(b"/*") {
            *state = 1;
            index += 2;
            if let Some(end) = line[index..].find("*/") {
                index += end + 2;
                *state = 0;
            } else {
                index = bytes.len();
            }
            append(line, output, &mut count, start, index, 2);
            continue;
        }
        if bytes[index] == b'"' || bytes[index] == b'\'' {
            let quote = bytes[index];
            index += 1;
            while index < bytes.len() {
                if bytes[index] == b'\\' {
                    index = (index + 2).min(bytes.len());
                } else if bytes[index] == quote {
                    index += 1;
                    break;
                } else {
                    index += 1;
                }
            }
            append(line, output, &mut count, start, index, 1);
            continue;
        }
        if bytes[index].is_ascii_digit() {
            index += 1;
            while index < bytes.len()
                && (bytes[index].is_ascii_alphanumeric()
                    || matches!(bytes[index], b'.' | b'_' | b'\''))
            {
                index += 1;
            }
            append(line, output, &mut count, start, index, 3);
            continue;
        }
        if bytes[index].is_ascii_alphabetic() || bytes[index] == b'_' {
            index += 1;
            while index < bytes.len()
                && (bytes[index].is_ascii_alphanumeric() || bytes[index] == b'_')
            {
                index += 1;
            }
            let word = &line[start..index];
            let kind = if wordIn(word, TYPES) {
                Some(5)
            } else if wordIn(word, KEYWORDS) {
                Some(0)
            } else if matches!(word, "NULL" | "true" | "false" | "nullptr") {
                Some(4)
            } else if line[index..].trim_start().starts_with('(') {
                Some(6)
            } else {
                None
            };
            if let Some(kind) = kind {
                append(line, output, &mut count, start, index, kind);
            }
            continue;
        }
        index += line[index..]
            .chars()
            .next()
            .map(char::len_utf8)
            .unwrap_or(1);
    }
    count
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn highlightsCppAndMultilineComments() {
        let mut state = 0;
        let mut output = std::array::from_fn::<_, 16, _>(|_| SyntaxToken {
            startUtf16: 0,
            lengthUtf16: 0,
            kind: 0,
        });
        let count = tokens("constexpr int value = 42; /* open", &mut state, &mut output);
        assert!(count >= 4);
        assert_eq!(output[0].kind, 0);
        assert_eq!(output[1].kind, 5);
        assert_eq!(state, 1);
        let count = tokens("still */ return value;", &mut state, &mut output);
        assert_eq!(output[0].kind, 2);
        assert_eq!(output[1].kind, 0);
        assert!(count >= 2);
        assert_eq!(state, 0);
    }

    #[test]
    fn offsetsAreUtf16() {
        let mut state = 0;
        let mut output = [SyntaxToken {
            startUtf16: 0,
            lengthUtf16: 0,
            kind: 0,
        }];
        assert_eq!(tokens("😀 int", &mut state, &mut output), 1);
        assert_eq!(output[0].startUtf16, 3);
    }
}
