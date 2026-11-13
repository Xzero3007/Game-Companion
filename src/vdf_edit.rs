//! Changes Valve KeyValues text (`localconfig.vdf`, `config.vdf`) in place:
//! one value is replaced, added or removed, and every other byte of the file
//! stays exactly as it was (indentation, comments, order, unknown keys).
//! Keys are matched ignoring case, as Steam does.

/// One `"key" value` pair with the byte places of its parts.
#[derive(Debug)]
struct Entry {
    key: String,
    /// Where the key's token starts.
    key_start: usize,
    /// Where the key's token ends.
    key_end: usize,
    value: Node,
}

#[derive(Debug)]
enum Node {
    /// A string value: its token's place (quotes included) and its text.
    Str { start: usize, end: usize, text: String },
    /// A block: the place of `{`, of its `}` (None when the file ends
    /// first) and its entries.
    Block { open: usize, close: Option<usize>, children: Vec<Entry> },
}

impl Entry {
    /// The byte after the entry's value.
    fn end(&self, text_len: usize) -> usize {
        match &self.value {
            Node::Str { end, .. } => *end,
            Node::Block { close, .. } => close.map(|c| c + 1).unwrap_or(text_len),
        }
    }
}

#[derive(Debug)]
enum Token {
    Open(usize),
    Close(usize),
    Word { start: usize, end: usize, text: String },
}

fn tokens(text: &str) -> Vec<Token> {
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        let c = bytes[i];
        match c {
            b'{' => {
                out.push(Token::Open(i));
                i += 1;
            }
            b'}' => {
                out.push(Token::Close(i));
                i += 1;
            }
            b'"' => {
                let start = i;
                i += 1;
                let mut word = Vec::new();
                while i < bytes.len() {
                    match bytes[i] {
                        b'"' => {
                            i += 1;
                            break;
                        }
                        b'\\' if i + 1 < bytes.len() => {
                            match bytes[i + 1] {
                                b'n' => word.push(b'\n'),
                                b't' => word.push(b'\t'),
                                other => word.push(other),
                            }
                            i += 2;
                        }
                        other => {
                            word.push(other);
                            i += 1;
                        }
                    }
                }
                out.push(Token::Word { start, end: i.min(bytes.len()), text: String::from_utf8_lossy(&word).into_owned() });
            }
            b'/' if bytes.get(i + 1) == Some(&b'/') => {
                while i < bytes.len() && bytes[i] != b'\n' {
                    i += 1;
                }
            }
            c if c.is_ascii_whitespace() => i += 1,
            _ => {
                let start = i;
                while i < bytes.len() && !bytes[i].is_ascii_whitespace() && !matches!(bytes[i], b'{' | b'}' | b'"') {
                    i += 1;
                }
                let word = &text[start..i];
                // [$WIN32]-style conditions belong to the line before.
                if !(word.starts_with('[') && word.ends_with(']')) {
                    out.push(Token::Word { start, end: i, text: word.to_string() });
                }
            }
        }
    }
    out
}

/// Reads entries until the block's `}`; returns them and that `}`'s place.
fn block(tokens: &mut std::iter::Peekable<std::vec::IntoIter<Token>>) -> (Vec<Entry>, Option<usize>) {
    let mut entries = Vec::new();
    while let Some(token) = tokens.next() {
        match token {
            Token::Close(at) => return (entries, Some(at)),
            Token::Open(_) => {
                // A block without a key: skipped, as Steam's reader does.
                block(tokens);
            }
            Token::Word { start, end, text } => match tokens.peek() {
                Some(Token::Open(open)) => {
                    let open = *open;
                    tokens.next();
                    let (children, close) = block(tokens);
                    entries.push(Entry { key: text, key_start: start, key_end: end, value: Node::Block { open, close, children } });
                }
                Some(Token::Word { .. }) => {
                    if let Some(Token::Word { start: vs, end: ve, text: value }) = tokens.next() {
                        entries.push(Entry {
                            key: text,
                            key_start: start,
                            key_end: end,
                            value: Node::Str { start: vs, end: ve, text: value },
                        });
                    }
                }
                _ => {}
            },
        }
    }
    (entries, None)
}

fn parse(text: &str) -> Vec<Entry> {
    block(&mut tokens(text).into_iter().peekable()).0
}

fn find<'a>(entries: &'a [Entry], key: &str) -> Option<&'a Entry> {
    entries.iter().find(|e| e.key.eq_ignore_ascii_case(key))
}

/// A string value under a path of keys.
pub fn get_str(text: &str, path: &[&str]) -> Option<String> {
    let root = parse(text);
    let (last, parents) = path.split_last()?;
    let mut level: &[Entry] = &root;
    for key in parents {
        match &find(level, key)?.value {
            Node::Block { children, .. } => level = children,
            Node::Str { .. } => return None,
        }
    }
    match &find(level, last)?.value {
        Node::Str { text, .. } => Some(text.clone()),
        Node::Block { .. } => None,
    }
}

/// The keys of the entries under a path (for blocks keyed by number).
pub fn keys(text: &str, path: &[&str]) -> Vec<String> {
    let root = parse(text);
    let mut level: &[Entry] = &root;
    for key in path {
        match find(level, key).map(|e| &e.value) {
            Some(Node::Block { children, .. }) => level = children,
            _ => return Vec::new(),
        }
    }
    level.iter().map(|e| e.key.clone()).collect()
}

/// Text as a quoted KeyValues string.
pub fn quote(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for c in value.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// Where the line holding `at` starts, if only spaces and tabs come
/// before `at` on it.
fn line_start(text: &str, at: usize) -> Option<usize> {
    let start = text[..at].rfind('\n').map(|n| n + 1).unwrap_or(0);
    text[start..at].bytes().all(|b| b == b' ' || b == b'\t').then_some(start)
}

/// The indentation of the line holding `at` (empty when other text comes
/// first on that line).
fn indent_of(text: &str, at: usize) -> &str {
    line_start(text, at).map(|s| &text[s..at]).unwrap_or("")
}

/// Keys and a value as new lines, each at `indent` plus one tab per level.
fn build(keys: &[&str], value: &str, indent: &str, sep: &str) -> String {
    match keys.split_first() {
        None => String::new(),
        Some((key, [])) => format!("{indent}{}{sep}{}\n", quote(key), quote(value)),
        Some((key, rest)) => {
            let inner = format!("{indent}\t");
            format!("{indent}{}\n{indent}{{\n{}{indent}}}\n", quote(key), build(rest, value, &inner, sep))
        }
    }
}

/// Sets a string value under a path of keys. The first `must_exist` keys
/// must be there already (so a wrong file is never filled with a made-up
/// tree); the rest are added as needed, indented like their neighbours.
/// Returns the new text; everything else stays byte for byte.
pub fn set_str(text: &str, path: &[&str], value: &str, must_exist: usize) -> Result<String, String> {
    if path.is_empty() {
        return Err("No key given".into());
    }
    let root = parse(text);
    let mut level: &[Entry] = &root;
    // The block new keys go into: its `}` place and indentation.
    let mut parent: Option<&Entry> = None;
    for (depth, key) in path.iter().enumerate() {
        let last = depth + 1 == path.len();
        match find(level, key) {
            Some(entry) => match &entry.value {
                Node::Str { start, end, .. } if last => {
                    let mut out = String::with_capacity(text.len() + value.len());
                    out.push_str(&text[..*start]);
                    out.push_str(&quote(value));
                    out.push_str(&text[*end..]);
                    return Ok(out);
                }
                Node::Block { children, .. } if !last => {
                    parent = Some(entry);
                    level = children;
                }
                _ => return Err(format!("\"{key}\" has an unexpected form in the file")),
            },
            None => {
                if depth < must_exist {
                    return Err(format!("\"{key}\" was not found in the file"));
                }
                let Some(parent) = parent else {
                    return Err("The file has no block to add to".into());
                };
                let Node::Block { open, close: Some(close), children } = &parent.value else {
                    return Err("The file looks cut off".into());
                };
                // Indentation and separator from the last neighbour, else one
                // tab more than the block's own line.
                let indent = match children.last() {
                    Some(last) => indent_of(text, last.key_start).to_string(),
                    None => format!("{}\t", indent_of(text, *open)),
                };
                let sep = children
                    .iter()
                    .rev()
                    .find_map(|e| match &e.value {
                        Node::Str { start, .. } => {
                            let between = &text[e.key_end..*start];
                            (!between.is_empty() && between.bytes().all(|b| b == b' ' || b == b'\t')).then_some(between)
                        }
                        Node::Block { .. } => None,
                    })
                    .unwrap_or("\t\t");
                let new = build(&path[depth..], value, &indent, sep);
                let mut out = String::with_capacity(text.len() + new.len() + 1);
                match line_start(text, *close) {
                    Some(at) => {
                        out.push_str(&text[..at]);
                        out.push_str(&new);
                        out.push_str(&text[at..]);
                    }
                    None => {
                        // `}` shares its line with something else.
                        out.push_str(&text[..*close]);
                        out.push('\n');
                        out.push_str(&new);
                        out.push_str(indent_of(text, parent.key_start));
                        out.push_str(&text[*close..]);
                    }
                }
                return Ok(out);
            }
        }
    }
    unreachable!("the loop returns at the path's last key")
}

/// Removes the entry under a path (with its line when it has one to
/// itself). Missing entries leave the text as it is.
pub fn remove(text: &str, path: &[&str]) -> String {
    let root = parse(text);
    let Some((last, parents)) = path.split_last() else { return text.to_string() };
    let mut level: &[Entry] = &root;
    for key in parents {
        match find(level, key).map(|e| &e.value) {
            Some(Node::Block { children, .. }) => level = children,
            _ => return text.to_string(),
        }
    }
    let Some(entry) = find(level, last) else { return text.to_string() };
    let mut start = entry.key_start;
    let mut end = entry.end(text.len());
    if let Some(at) = line_start(text, start) {
        // Only blanks up to the line's end: the whole line goes.
        let rest = &text[end..];
        let blanks = rest.bytes().take_while(|b| *b == b' ' || *b == b'\t' || *b == b'\r').count();
        if rest[blanks..].starts_with('\n') {
            start = at;
            end += blanks + 1;
        } else if rest[blanks..].is_empty() {
            start = at;
            end += blanks;
        }
    }
    format!("{}{}", &text[..start], &text[end..])
}

#[cfg(test)]
mod tests {
    use super::*;

    const LOCAL: &str = "\"UserLocalConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t\t\"apps\"\n\t\t\t\t{\n\t\t\t\t\t\"10\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"LastPlayed\"\t\t\"1700000000\"\n\t\t\t\t\t\t\"LaunchOptions\"\t\t\"-novid \\\"x\\\"\"\n\t\t\t\t\t}\n\t\t\t\t\t\"20\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"LastPlayed\"\t\t\"1\"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n\t// a comment\n\t\"friends\" { \"x\" \"y\" }\n}\n";

    const APPS: [&str; 5] = ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps"];

    fn path<'a>(extra: &[&'a str]) -> Vec<&'a str> {
        APPS.iter().copied().chain(extra.iter().copied()).collect()
    }

    #[test]
    fn reads_values_ignoring_case() {
        assert_eq!(get_str(LOCAL, &path(&["10", "LaunchOptions"])).as_deref(), Some("-novid \"x\""));
        assert_eq!(get_str(LOCAL, &["userlocalconfigstore", "SOFTWARE", "valve", "steam", "Apps", "10", "launchoptions"]).as_deref(), Some("-novid \"x\""));
        assert_eq!(get_str(LOCAL, &path(&["20", "LaunchOptions"])), None);
        assert_eq!(keys(LOCAL, &APPS), vec!["10", "20"]);
    }

    #[test]
    fn replaces_a_value_and_keeps_the_rest() {
        let out = set_str(LOCAL, &path(&["10", "LaunchOptions"]), "gamemoderun %command% \\o/", 4).unwrap();
        assert_eq!(out, LOCAL.replace("\"-novid \\\"x\\\"\"", "\"gamemoderun %command% \\\\o/\""));
        assert_eq!(get_str(&out, &path(&["10", "LaunchOptions"])).as_deref(), Some("gamemoderun %command% \\o/"));
    }

    #[test]
    fn adds_a_value_indented_like_its_neighbours() {
        let out = set_str(LOCAL, &path(&["20", "LaunchOptions"]), "-x", 4).unwrap();
        let expected = LOCAL.replace(
            "\"LastPlayed\"\t\t\"1\"\n",
            "\"LastPlayed\"\t\t\"1\"\n\t\t\t\t\t\t\"LaunchOptions\"\t\t\"-x\"\n",
        );
        assert_eq!(out, expected);
    }

    #[test]
    fn adds_missing_blocks() {
        let out = set_str(LOCAL, &path(&["30", "LaunchOptions"]), "-y", 4).unwrap();
        let added = "\t\t\t\t\t\"30\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"LaunchOptions\"\t\t\"-y\"\n\t\t\t\t\t}\n";
        let expected = LOCAL.replace("\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n\t// a comment", &format!("{added}\t\t\t\t}}\n\t\t\t}}\n\t\t}}\n\t}}\n\t// a comment"));
        assert_eq!(out, expected);
        assert_eq!(get_str(&out, &path(&["30", "LaunchOptions"])).as_deref(), Some("-y"));
        // A whole missing "apps" block under an empty "Steam" block.
        let bare = "\"UserLocalConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t}\n\t\t}\n\t}\n}\n";
        let out = set_str(bare, &path(&["5", "LaunchOptions"]), "a", 4).unwrap();
        assert_eq!(get_str(&out, &path(&["5", "LaunchOptions"])).as_deref(), Some("a"));
        assert!(out.contains("\t\t\t\t\"apps\"\n\t\t\t\t{\n\t\t\t\t\t\"5\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"LaunchOptions\"\t\t\"a\"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n"));
    }

    #[test]
    fn refuses_strange_files() {
        assert!(set_str("\"Other\" { }", &path(&["1", "LaunchOptions"]), "x", 4).is_err());
        assert!(set_str("", &path(&["1", "LaunchOptions"]), "x", 4).is_err());
        // Cut off before the block's end.
        let cut = "\"UserLocalConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n";
        assert!(set_str(cut, &path(&["1", "LaunchOptions"]), "x", 4).is_err());
        // A value where a block should be.
        let odd = LOCAL.replace("\"20\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"LastPlayed\"\t\t\"1\"\n\t\t\t\t\t}", "\"20\" \"x\"");
        assert!(set_str(&odd, &path(&["20", "LaunchOptions"]), "x", 4).is_err());
    }

    #[test]
    fn closing_brace_on_a_shared_line() {
        let text = "\"a\" { \"b\" { \"c\" \"1\" } }";
        let out = set_str(text, &["a", "b", "d"], "2", 2).unwrap();
        assert_eq!(get_str(&out, &["a", "b", "d"]).as_deref(), Some("2"));
        assert_eq!(get_str(&out, &["a", "b", "c"]).as_deref(), Some("1"));
    }

    #[test]
    fn removes_whole_lines_only() {
        let out = remove(LOCAL, &path(&["10", "LaunchOptions"]));
        assert_eq!(out, LOCAL.replace("\t\t\t\t\t\t\"LaunchOptions\"\t\t\"-novid \\\"x\\\"\"\n", ""));
        let out = remove(LOCAL, &path(&["20"]));
        assert_eq!(out, LOCAL.replace("\t\t\t\t\t\"20\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"LastPlayed\"\t\t\"1\"\n\t\t\t\t\t}\n", ""));
        assert_eq!(remove(LOCAL, &path(&["99"])), LOCAL);
        let inline = "\"a\" { \"b\" \"1\" \"c\" \"2\" }";
        assert_eq!(remove(inline, &["a", "b"]), "\"a\" {  \"c\" \"2\" }");
    }

    #[test]
    fn quotes_like_steam() {
        assert_eq!(quote("a\"b\\c"), "\"a\\\"b\\\\c\"");
    }
}
