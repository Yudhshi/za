//! 同期フォルダ。各端末は自分の `english-events-<端末>.jsonl` だけを書き、全員のファイルを読む。
//! 書くときは同じフォルダの `.english-events-<端末>.jsonl.tmp` に書いてから置き換える(書きかけを読ませない)。
//! 中身が変わらなければ書かない(同期盘が同じ内容を何度も上げないように)

use std::collections::HashSet;
use std::io;
use std::path::{Path, PathBuf};

use crate::event::SyncEvent;

/// ファイル名に使える端末名(英数字と - _ 以外は -、両端の - は落とす。空なら device)
pub fn slug(device: &str) -> String {
    let mapped: String = device
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '-'
            }
        })
        .collect();
    let trimmed = mapped.trim_matches('-');
    if trimmed.is_empty() {
        "device".into()
    } else {
        trimmed.into()
    }
}

pub fn file_name(device: &str) -> String {
    format!("english-events-{}.jsonl", slug(device))
}

/// 一時ファイルに書いてから置き換える(Windows の rename は既存のファイルを置き換える)。同じ内容なら false
pub fn write_atomic(path: &Path, text: &str) -> io::Result<bool> {
    if std::fs::read_to_string(path).is_ok_and(|old| old == text) {
        return Ok(false);
    }
    let dir = path.parent().unwrap_or(Path::new("."));
    std::fs::create_dir_all(dir)?;
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let temp = dir.join(format!(".{name}.tmp"));
    std::fs::write(&temp, text)?;
    std::fs::rename(&temp, path)?;
    Ok(true)
}

#[derive(Clone, Debug)]
pub struct SyncFolder {
    pub root: PathBuf,
    pub device: String,
}

impl SyncFolder {
    pub fn new(root: impl Into<PathBuf>, device: &str) -> SyncFolder {
        SyncFolder {
            root: root.into(),
            device: device.to_string(),
        }
    }

    pub fn own_file(&self) -> PathBuf {
        self.root.join(file_name(&self.device))
    }

    /// 語表の置き場所(Mac が書く)
    pub fn library_dir(&self) -> PathBuf {
        self.root.join("english-library")
    }

    fn read_file(path: &Path) -> Vec<SyncEvent> {
        std::fs::read_to_string(path)
            .map(|text| text.lines().filter_map(SyncEvent::parse).collect())
            .unwrap_or_default()
    }

    /// 自分の出来事(ファイルの順 = 起きた順)
    pub fn own_events(&self) -> Vec<SyncEvent> {
        Self::read_file(&self.own_file())
    }

    /// 全端末の出来事(自分のも含む)。id で重複を除く。読めないファイル・行は飛ばす
    pub fn all_events(&self) -> Vec<SyncEvent> {
        let mut files: Vec<PathBuf> = std::fs::read_dir(&self.root)
            .map(|entries| {
                entries
                    .filter_map(|e| e.ok().map(|e| e.path()))
                    .filter(|p| {
                        let name = p.file_name().map(|n| n.to_string_lossy().into_owned());
                        name.is_some_and(|n| {
                            n.starts_with("english-events-") && n.ends_with(".jsonl")
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();
        files.sort();
        let mut seen = HashSet::new();
        let mut events = Vec::new();
        for file in files {
            for event in Self::read_file(&file) {
                if seen.insert(event.id.clone()) {
                    events.push(event);
                }
            }
        }
        events
    }

    /// 自分の出来事を全部書き出す(1 行 1 件、最後に改行)
    pub fn write_own(&self, events: &[SyncEvent]) -> io::Result<bool> {
        let mut text: String = events
            .iter()
            .map(|e| e.json_line())
            .collect::<Vec<_>>()
            .join("\n");
        if !events.is_empty() {
            text.push('\n');
        }
        write_atomic(&self.own_file(), &text)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::day::testing::tokyo;
    use crate::event::Op;

    pub(crate) fn temp_dir() -> PathBuf {
        let dir = std::env::temp_dir().join(format!("yudh-sync-{}", crate::event::new_id()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn device_names_become_file_names() {
        assert_eq!(slug("Mac Book (Yudh)"), "Mac-Book--Yudh");
        assert_eq!(file_name("DESKTOP-9F2"), "english-events-DESKTOP-9F2.jsonl");
        assert_eq!(slug("  "), "device");
        assert_eq!(slug("--a--"), "a");
    }

    #[test]
    fn writes_own_file_reads_everyone_skips_garbage() {
        let dir = temp_dir();
        let pc = SyncFolder::new(&dir, "PC");
        let mut e = SyncEvent::new("PC", tokyo(2026, 10, 1, 10, 0, 0), Op::Add);
        e.card = Some("dict:x".into());
        e.kind = Some("vocab".into());
        assert!(pc.write_own(std::slice::from_ref(&e)).unwrap(), "written");
        assert!(
            !pc.write_own(std::slice::from_ref(&e)).unwrap(),
            "same content: untouched"
        );
        assert!(
            !dir.join(".english-events-PC.jsonl.tmp").exists(),
            "no temp left"
        );
        // Mac のファイル(壊れた行と、自分と同じ出来事の重複を含む)
        let mac_line = SyncEvent::new("Mac", tokyo(2026, 10, 1, 9, 0, 0), Op::Add).json_line();
        std::fs::write(
            dir.join("english-events-Mac.jsonl"),
            format!("{mac_line}\nnot json\n{}\n", e.json_line()),
        )
        .unwrap();
        std::fs::write(dir.join("agenda.json"), "{}").unwrap();
        let all = pc.all_events();
        assert_eq!(
            all.len(),
            2,
            "deduplicated by id, garbage skipped, other files ignored"
        );
        assert_eq!(pc.own_events(), vec![e]);
        std::fs::remove_dir_all(&dir).ok();
    }
}
