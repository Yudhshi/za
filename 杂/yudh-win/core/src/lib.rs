//! Yudh for Windows の中身(画面なし)。Mac 版(Swift の NippoCore)と同じ規則で動く:
//!
//! - 英語の進捗:同期フォルダの `english-events-<端末>.jsonl` を全部読み、出来事を時刻順に再生する(`sync` / `replay`)。
//!   ローカルのデータベースは持たない。自分のファイルが自分の出来事の正本
//! - 間隔反復(SM-2)・出題の順番・聴写の採点・同義替換の 4 択(`srs` / `queue` / `spell` / `quiz`)
//! - 素材(語表)は同期フォルダの `english-library/` から読む(`library`)。語表は git に入れない
//! - 会議:Mac が書く `agenda.json` を読むだけ(`agenda`)
//! - 坐站の切り替え:計時と小窓の判定だけ(`posture`)。全画面のゲーム中は出さない
//!
//! 書式は Mac 側の `docs/sync-format.md` が正本。数字はどちらのテストでも同じになるようにしてある

pub mod agenda;
pub mod day;
pub mod english;
pub mod event;
pub mod library;
pub mod posture;
pub mod queue;
pub mod quiz;
pub mod replay;
pub mod round;
pub mod spell;
pub mod srs;
pub mod sync;

pub use day::Zone;
pub use english::{English, UndoPoint};
pub use event::{Op, SyncEvent};
pub use srs::{Rating, SrsState};
