//! Steam's `appcache/appinfo.vdf`: the binary file in which the Steam
//! client keeps what it knows about apps (name, type, ...). Only read, and
//! only the entries asked for are decoded: the file can be over 100 MB, so
//! it is streamed and every other entry is skipped by its size. What was
//! found is kept per file until the file changes (size or time).

use std::collections::{BTreeSet, HashMap};
use std::io::{BufRead, BufReader, Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::SystemTime;

use crate::games::Vdf;

/// What an app is, as far as the library needs it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppMeta {
    pub name: String,
    /// `common.type` in lower case: "game", "tool", "dlc", "music",
    /// "application", "demo", ...
    pub kind: String,
}

const MAGIC_27: u32 = 0x0756_4427;
const MAGIC_28: u32 = 0x0756_4428;
const MAGIC_29: u32 = 0x0756_4429;
/// Limits against broken files: one entry, the v29 key table, one key.
const MAX_ENTRY: usize = 16 << 20;
const MAX_STRINGS: usize = 1 << 20;
const MAX_STRING: usize = 4096;

/// Binary KeyValues types.
const KV_MAP: u8 = 0;
const KV_STRING: u8 = 1;
const KV_INT: u8 = 2;
const KV_FLOAT: u8 = 3;
const KV_PTR: u8 = 4;
const KV_WSTRING: u8 = 5;
const KV_COLOR: u8 = 6;
const KV_UINT64: u8 = 7;
const KV_END: u8 = 8;
const KV_INT64: u8 = 10;
const KV_END_ALT: u8 = 11;

fn u32_at(b: &[u8]) -> Option<u32> {
    Some(u32::from_le_bytes(b.get(..4)?.try_into().ok()?))
}

struct Reader<'a> {
    data: &'a [u8],
    at: usize,
    strings: Option<&'a [String]>,
}

impl Reader<'_> {
    fn byte(&mut self) -> Option<u8> {
        let b = *self.data.get(self.at)?;
        self.at += 1;
        Some(b)
    }

    fn take(&mut self, n: usize) -> Option<&[u8]> {
        let s = self.data.get(self.at..self.at.checked_add(n)?)?;
        self.at += n;
        Some(s)
    }

    fn cstr(&mut self) -> Option<String> {
        let rest = self.data.get(self.at..)?;
        let end = rest.iter().position(|&b| b == 0)?;
        let s = String::from_utf8_lossy(&rest[..end]).into_owned();
        self.at += end + 1;
        Some(s)
    }

    fn wstr(&mut self) -> Option<String> {
        let mut units = Vec::new();
        loop {
            let u = u16::from_le_bytes(self.take(2)?.try_into().ok()?);
            if u == 0 {
                break;
            }
            units.push(u);
        }
        Some(String::from_utf16_lossy(&units))
    }

    fn key(&mut self) -> Option<String> {
        match self.strings {
            Some(table) => table.get(u32_at(self.take(4)?)? as usize).cloned(),
            None => self.cstr(),
        }
    }

    fn map(&mut self, depth: usize) -> Option<Vec<(String, Vdf)>> {
        if depth > 64 {
            return None;
        }
        let mut items = Vec::new();
        loop {
            let kind = self.byte()?;
            if kind == KV_END || kind == KV_END_ALT {
                return Some(items);
            }
            let key = self.key()?;
            let value = match kind {
                KV_MAP => Vdf::Map(self.map(depth + 1)?),
                KV_STRING => Vdf::Str(self.cstr()?),
                KV_WSTRING => Vdf::Str(self.wstr()?),
                KV_INT => Vdf::Str(i32::from_le_bytes(self.take(4)?.try_into().ok()?).to_string()),
                KV_FLOAT => Vdf::Str(f32::from_le_bytes(self.take(4)?.try_into().ok()?).to_string()),
                KV_PTR | KV_COLOR => Vdf::Str(u32_at(self.take(4)?)?.to_string()),
                KV_UINT64 => Vdf::Str(u64::from_le_bytes(self.take(8)?.try_into().ok()?).to_string()),
                KV_INT64 => Vdf::Str(i64::from_le_bytes(self.take(8)?.try_into().ok()?).to_string()),
                _ => return None,
            };
            items.push((key, value));
        }
    }
}

/// Reads binary KeyValues from `data`. Keys are inline strings, or (v29)
/// numbers into `strings`. Numbers become text. None for broken data.
pub fn parse_binary_kv(data: &[u8], strings: Option<&[String]>) -> Option<Vdf> {
    let mut r = Reader { data, at: 0, strings };
    // The top level ends with an end mark (or with the data).
    let mut items = Vec::new();
    while r.at < data.len() {
        let kind = r.byte()?;
        if kind == KV_END || kind == KV_END_ALT {
            break;
        }
        let key = r.key()?;
        if kind != KV_MAP {
            return None;
        }
        items.push((key, Vdf::Map(r.map(1)?)));
    }
    Some(Vdf::Map(items))
}

fn meta_of(kv: &Vdf) -> Option<AppMeta> {
    let common = kv.get("appinfo")?.get("common")?;
    let name = common.str("name").unwrap_or("").trim().to_string();
    let kind = common.str("type").unwrap_or("").trim().to_ascii_lowercase();
    Some(AppMeta { name, kind })
}

fn read_u32(r: &mut impl Read) -> Option<u32> {
    let mut b = [0u8; 4];
    r.read_exact(&mut b).ok()?;
    Some(u32::from_le_bytes(b))
}

/// The entries of `wanted` that the file has, read in one pass (a cut
/// file gives what came before the cut).
pub fn read(path: &Path, wanted: &BTreeSet<u32>) -> HashMap<u32, AppMeta> {
    let mut found = HashMap::new();
    read_into(path, wanted, &mut found);
    found
}

fn read_into(path: &Path, wanted: &BTreeSet<u32>, found: &mut HashMap<u32, AppMeta>) -> Option<()> {
    if wanted.is_empty() {
        return None;
    }
    let file = std::fs::File::open(path).ok()?;
    let mut r = BufReader::with_capacity(256 * 1024, file);
    let magic = read_u32(&mut r)?;
    let _universe = read_u32(&mut r)?;
    // Per entry before its KeyValues: state, time, token, SHA-1, change
    // number, and from v28 the binary data's SHA-1.
    let head = match magic {
        MAGIC_27 => 40,
        MAGIC_28 | MAGIC_29 => 60,
        _ => return None,
    };
    let mut strings: Option<Vec<String>> = None;
    if magic == MAGIC_29 {
        // v29 (Steam, June 2024): keys are numbers into a table at
        // the end of the file.
        let mut b = [0u8; 8];
        r.read_exact(&mut b).ok()?;
        let offset = u64::try_from(i64::from_le_bytes(b)).ok()?;
        let start = r.stream_position().ok()?;
        r.seek(SeekFrom::Start(offset)).ok()?;
        let count = read_u32(&mut r)? as usize;
        // A broken file must not make us build a huge table.
        if count > MAX_STRINGS {
            return None;
        }
        let mut table = Vec::with_capacity(count);
        for _ in 0..count {
            let mut s = Vec::new();
            (&mut r).take(MAX_STRING as u64).read_until(0, &mut s).ok()?;
            if s.pop() != Some(0) {
                return None;
            }
            table.push(String::from_utf8_lossy(&s).into_owned());
        }
        strings = Some(table);
        r.seek(SeekFrom::Start(start)).ok()?;
    }
    let mut buffer = Vec::new();
    loop {
        let appid = read_u32(&mut r)?;
        if appid == 0 {
            return Some(());
        }
        let size = read_u32(&mut r)? as usize;
        // Real entries are kilobytes; a size beyond that is a broken file.
        if size > MAX_ENTRY {
            return None;
        }
        if !wanted.contains(&appid) {
            r.seek_relative(size as i64).ok()?;
            continue;
        }
        buffer.resize(size, 0);
        r.read_exact(&mut buffer).ok()?;
        if let Some(meta) = buffer.get(head..).and_then(|d| parse_binary_kv(d, strings.as_deref())).and_then(|kv| meta_of(&kv)) {
            found.insert(appid, meta);
        }
        if found.len() == wanted.len() {
            return Some(());
        }
    }
}

/// What was read from one file, for as long as the file stays the same.
struct Cached {
    path: PathBuf,
    stamp: (SystemTime, u64),
    /// Each app asked about: what the file says, or None (not in it).
    apps: HashMap<u32, Option<AppMeta>>,
}

fn cache() -> &'static Mutex<Vec<Cached>> {
    static CACHE: OnceLock<Mutex<Vec<Cached>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(Vec::new()))
}

/// `read`, but only the apps not asked about before are read from the
/// file (all again after it changed).
pub fn lookup(path: &Path, wanted: &BTreeSet<u32>) -> HashMap<u32, AppMeta> {
    let Ok(info) = std::fs::metadata(path) else { return HashMap::new() };
    let stamp = (info.modified().unwrap_or(SystemTime::UNIX_EPOCH), info.len());
    let mut all = cache().lock().unwrap_or_else(|p| p.into_inner());
    let index = match all.iter().position(|c| c.path == path) {
        Some(i) => {
            if all[i].stamp != stamp {
                all[i] = Cached { path: path.to_path_buf(), stamp, apps: HashMap::new() };
            }
            i
        }
        None => {
            all.push(Cached { path: path.to_path_buf(), stamp, apps: HashMap::new() });
            all.len() - 1
        }
    };
    let entry = &mut all[index];
    let missing: BTreeSet<u32> = wanted.iter().copied().filter(|id| !entry.apps.contains_key(id)).collect();
    if !missing.is_empty() {
        let mut found = read(path, &missing);
        for id in missing {
            entry.apps.insert(id, found.remove(&id));
        }
    }
    wanted.iter().filter_map(|id| Some((*id, entry.apps.get(id)?.clone()?))).collect()
}

#[cfg(test)]
pub mod fixture {
    //! Writes small appinfo.vdf files in the real layouts, for tests.

    /// One app: its id, name and type, plus filler of `pad` bytes (an
    /// unwanted entry must be skipped by its size).
    pub struct App<'a> {
        pub id: u32,
        pub name: &'a str,
        pub kind: &'a str,
        pub pad: usize,
    }

    /// `version` 27, 28 or 29.
    pub fn appinfo(version: u32, apps: &[App]) -> Vec<u8> {
        let mut table: Vec<String> = Vec::new();
        let mut key = |out: &mut Vec<u8>, k: &str| {
            if version == 29 {
                let i = table.iter().position(|t| t == k).unwrap_or_else(|| {
                    table.push(k.to_string());
                    table.len() - 1
                });
                out.extend_from_slice(&(i as u32).to_le_bytes());
            } else {
                out.extend_from_slice(k.as_bytes());
                out.push(0);
            }
        };
        let mut body = Vec::new();
        for app in apps {
            let mut kv = vec![0];
            key(&mut kv, "appinfo");
            kv.push(2);
            key(&mut kv, "appid");
            kv.extend_from_slice(&app.id.to_le_bytes());
            kv.push(0);
            key(&mut kv, "common");
            kv.push(1);
            key(&mut kv, "name");
            kv.extend_from_slice(app.name.as_bytes());
            kv.push(0);
            kv.push(1);
            key(&mut kv, "type");
            kv.extend_from_slice(app.kind.as_bytes());
            kv.push(0);
            kv.push(7);
            key(&mut kv, "gameid");
            kv.extend_from_slice(&u64::from(app.id).to_le_bytes());
            kv.push(5);
            key(&mut kv, "wide");
            for u in "w".encode_utf16() {
                kv.extend_from_slice(&u.to_le_bytes());
            }
            kv.extend_from_slice(&[0, 0]);
            kv.push(8); // common
            kv.push(1);
            key(&mut kv, "filler");
            kv.extend(std::iter::repeat_n(b'x', app.pad));
            kv.push(0);
            kv.push(8); // appinfo
            kv.push(8); // top
            let head = if version == 27 { 40 } else { 60 };
            let mut entry = vec![0u8; head];
            entry.extend_from_slice(&kv);
            body.extend_from_slice(&app.id.to_le_bytes());
            body.extend_from_slice(&(entry.len() as u32).to_le_bytes());
            body.extend_from_slice(&entry);
        }
        body.extend_from_slice(&0u32.to_le_bytes());
        let magic = 0x0756_4400u32 + 0x20 + (version - 20);
        let mut out = Vec::new();
        out.extend_from_slice(&magic.to_le_bytes());
        out.extend_from_slice(&1u32.to_le_bytes());
        if version == 29 {
            let offset = (out.len() + 8 + body.len()) as i64;
            out.extend_from_slice(&offset.to_le_bytes());
            out.extend_from_slice(&body);
            out.extend_from_slice(&(table.len() as u32).to_le_bytes());
            for t in &table {
                out.extend_from_slice(t.as_bytes());
                out.push(0);
            }
        } else {
            out.extend_from_slice(&body);
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::fixture::{appinfo, App};
    use super::*;

    fn apps() -> Vec<App<'static>> {
        vec![
            App { id: 10, name: "Counter-Strike", kind: "Game", pad: 0 },
            App { id: 228_980, name: "Steamworks Common Redistributables", kind: "Tool", pad: 5000 },
            App { id: 300_000, name: "A Soundtrack", kind: "Music", pad: 10 },
            App { id: 400_000, name: "Späte Spiele", kind: "game", pad: 0 },
        ]
    }

    #[test]
    fn reads_every_version_and_skips_the_rest() {
        let dir = std::env::temp_dir().join(format!("gc-appinfo-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        for version in [27, 28, 29] {
            let path = dir.join(format!("appinfo{version}.vdf"));
            std::fs::write(&path, appinfo(version, &apps())).unwrap();
            let wanted: BTreeSet<u32> = [10, 300_000, 400_000, 999].into();
            let found = read(&path, &wanted);
            assert_eq!(found.len(), 3, "version {version}");
            assert_eq!(found[&10], AppMeta { name: "Counter-Strike".into(), kind: "game".into() });
            assert_eq!(found[&300_000].kind, "music");
            assert_eq!(found[&400_000].name, "Späte Spiele");
            // Through the cache: asked again, and with a new id.
            let again = lookup(&path, &[10, 228_980].into());
            assert_eq!(again[&228_980].kind, "tool");
            assert_eq!(again[&10].name, "Counter-Strike");
            assert!(lookup(&path, &[999].into()).is_empty());
        }
        // Not an appinfo file, a cut file, a missing file.
        let bad = dir.join("bad.vdf");
        std::fs::write(&bad, b"nonsense").unwrap();
        assert!(read(&bad, &[10].into()).is_empty());
        let mut cut = appinfo(28, &apps());
        cut.truncate(cut.len() / 2);
        std::fs::write(&bad, &cut).unwrap();
        assert_eq!(read(&bad, &[10, 400_000].into()).len(), 1);
        assert!(lookup(&dir.join("missing.vdf"), &[10].into()).is_empty());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn broken_kv_gives_nothing() {
        assert_eq!(parse_binary_kv(&[0, b'a', 0, 1, b'k', 0], None), None);
        assert_eq!(parse_binary_kv(&[9, b'a', 0], None), None);
        assert_eq!(parse_binary_kv(&[], None), Some(Vdf::Map(vec![])));
    }
}
