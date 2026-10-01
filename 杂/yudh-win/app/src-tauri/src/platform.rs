//! Windows だけの情報:最後の操作からの秒数(離席の判定)と、全画面のゲーム・プレゼン中か(小窓を出さない)。
//! ほかの OS(開発中の Linux など)では「操作中・全画面ではない」とみなす

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

#[cfg(not(windows))]
pub fn idle_seconds() -> u64 {
    0
}

#[cfg(not(windows))]
pub fn fullscreen_busy() -> bool {
    false
}
