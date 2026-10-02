//! Windows だけの情報:最後の操作からの秒数(離席の判定)と、全画面のゲーム・プレゼン中か(小窓を出さない)と、
//! 動いているプログラムの名前(打游戏时让 Yudh 完全安静)。
//! ほかの OS(開発中の Linux など)では「操作中・全画面ではない・何も動いていない」とみなす

#[cfg(windows)]
pub fn idle_seconds() -> u64 {
    use windows_sys::Win32::System::SystemInformation::GetTickCount;
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::{GetLastInputInfo, LASTINPUTINFO};
    let mut info = LASTINPUTINFO {
        cbSize: std::mem::size_of::<LASTINPUTINFO>() as u32,
        dwTime: 0,
    };
    // SAFETY: info は呼び出しのあいだ生きている、cbSize を入れた構造体
    let ok = unsafe { GetLastInputInfo(&mut info) };
    if ok == 0 {
        return 0;
    }
    // SAFETY: 引数なし
    let now = unsafe { GetTickCount() };
    u64::from(now.wrapping_sub(info.dwTime) / 1000)
}

#[cfg(windows)]
pub fn fullscreen_busy() -> bool {
    use windows_sys::Win32::UI::Shell::{
        SHQueryUserNotificationState, QUNS_BUSY, QUNS_PRESENTATION_MODE,
        QUNS_RUNNING_D3D_FULL_SCREEN,
    };
    let mut state = 0;
    // SAFETY: state は呼び出しのあいだ生きている
    let hr = unsafe { SHQueryUserNotificationState(&mut state) };
    hr == 0
        && (state == QUNS_BUSY
            || state == QUNS_RUNNING_D3D_FULL_SCREEN
            || state == QUNS_PRESENTATION_MODE)
}

/// 動いているプログラムの exe 名(タスクマネージャーの「詳細」と同じ一覧)。
/// 一覧の写しを撮るだけで、どのプロセスも開かない(ゲームのプロセスに触らない)
#[cfg(windows)]
pub fn running_process_names() -> Vec<String> {
    use windows_sys::Win32::Foundation::{CloseHandle, INVALID_HANDLE_VALUE};
    use windows_sys::Win32::System::Diagnostics::ToolHelp::{
        CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W,
        TH32CS_SNAPPROCESS,
    };
    let mut names = Vec::new();
    // SAFETY: 引数は定数。戻り値の HANDLE は下で必ず閉じる
    let snapshot = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) };
    if snapshot == INVALID_HANDLE_VALUE || snapshot.is_null() {
        return names;
    }
    // SAFETY: PROCESSENTRY32W は数値と配列だけの構造体(全部 0 で正しい値)
    let mut entry: PROCESSENTRY32W = unsafe { std::mem::zeroed() };
    entry.dwSize = std::mem::size_of::<PROCESSENTRY32W>() as u32;
    // SAFETY: snapshot は有効、entry は dwSize を入れた、呼び出しのあいだ生きている構造体
    let mut ok = unsafe { Process32FirstW(snapshot, &mut entry) };
    while ok != 0 {
        let len = entry
            .szExeFile
            .iter()
            .position(|&c| c == 0)
            .unwrap_or(entry.szExeFile.len());
        names.push(String::from_utf16_lossy(&entry.szExeFile[..len]));
        // SAFETY: 同上
        ok = unsafe { Process32NextW(snapshot, &mut entry) };
    }
    // SAFETY: CreateToolhelp32Snapshot が返した有効な HANDLE
    unsafe { CloseHandle(snapshot) };
    names
}

#[cfg(not(windows))]
pub fn running_process_names() -> Vec<String> {
    Vec::new()
}

#[cfg(not(windows))]
pub fn idle_seconds() -> u64 {
    0
}

#[cfg(not(windows))]
pub fn fullscreen_busy() -> bool {
    false
}
