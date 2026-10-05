//! Yudh for Windows の中身(画面なし)。Mac 版(Swift の NippoCore)と同じ規則で動く:
//!
//! - 英語の進捗:同期フォルダの `english-events-<端末>.jsonl` を全部読み、出来事を時刻順に再生する(`sync` / `replay`)。
//!   ローカルのデータベースは持たない。自分のファイルが自分の出来事の正本
//! - 間隔反復(SM-2)・出題の順番・聴写の採点・同義替換の 4 択(`srs` / `queue` / `spell` / `quiz`)
//! - 素材(語表)は同期フォルダの `english-library/` から読む(`library`)。語表は git に入れない
//! - 会議:Mac が書く `agenda.json` を読むだけ(`agenda`)
//! - 坐站の切り替え:播报の钟(時間が来たら自分で切り替えて言う。`posture`)と、一日の立った時間の記録(`standing`)。全画面のゲーム中は出さない
//! - 打游戏时让 Yudh 完全安静的程序の名単(`quiet`。AION2 など反作弊の厳しいゲーム)
//! - 泡澡のあとの日课と腹式呼吸の習慣(`ritual`)。記録は端末ごとの `habits-<端末>.json` で共有する(`habits`)
//!
//! 書式は Mac 側の `docs/sync-format.md` が正本。数字はどちらのテストでも同じになるようにしてある

pub mod agenda;
pub mod day;
pub mod english;
pub mod event;
pub mod habits;
pub mod library;
pub mod posture;
pub mod queue;
pub mod quiet;
pub mod quiz;
pub mod replay;
pub mod ritual;
pub mod round;
pub mod spell;
pub mod srs;
pub mod standing;
pub mod sync;

pub use day::Zone;
pub use english::{English, UndoPoint};
pub use event::{Op, SyncEvent};
pub use srs::{Rating, SrsState};
