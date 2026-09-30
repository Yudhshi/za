import AppKit
import SwiftUI

/// 面板の窓(v9):状態バーの項目を押すと画面の中央に浮いて出る。曜日の行を掴んで動かせ、動かした位置は覚える。
/// 外を押すか Esc、または状態バーの項目をもう一度押すと閉じる。
/// アプリをアクティブにしない(打鍵中のアプリはそのまま)が、窓自体は key になるので文字入力とショートカットは効く
@MainActor
final class MainPanelController: NSObject, NSWindowDelegate {
    private unowned let coordinator: AppCoordinator
    private let panel: NSPanel
    private var monitors: [Any] = []
    private var programmaticMove = false
    /// この窓の中の mouseDown は「外を押した」扱いにしない(状態バーの項目)
    weak var ignoredWindow: NSWindow?

    private static let topLeftKey = "panelTopLeft"

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: 400),
                             styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                             backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        // 開くたびに中身を作り直す(onAppear で日程を読み直し、選んだ会議を戻す。MenuBarExtra と同じ振る舞い)
        let root = PanelRoot(coordinator: coordinator) { [weak self] size in
            self?.fit(size)
        }
        let host = NSHostingView(rootView: root)
        // 初回の大きさは intrinsic で測り、その後は PanelRoot が知らせる高さで決める
        host.sizingOptions = [.intrinsicContentSize]
        let initial = host.intrinsicContentSize
        host.sizingOptions = []
        panel.contentView = host
        place(size: initial.width > 0 && initial.height > 0 ? initial
                    : CGSize(width: Theme.panelWidth, height: 400))
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installMonitors()
    }

    func hide() {
        removeMonitors()
        panel.orderOut(nil)
        panel.contentView = nil   // onDisappear(英語の再生の状態を戻す)
    }

    /// 動かした位置(左上)。画面の外なら忘れる
    private var savedTopLeft: CGPoint? {
        get {
            guard let a = UserDefaults.standard.array(forKey: Self.topLeftKey) as? [Double], a.count == 2 else { return nil }
            let p = CGPoint(x: a[0], y: a[1])
            return NSScreen.screens.contains { $0.visibleFrame.insetBy(dx: -20, dy: -20).contains(p) } ? p : nil
        }
        set {
            if let p = newValue {
                UserDefaults.standard.set([Double(p.x), Double(p.y)], forKey: Self.topLeftKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.topLeftKey)
            }
        }
    }

    /// 初めては画面(マウスのある画面)の中央、動かしたことがあればその位置(左上を合わせる)
    private func place(size: CGSize) {
        let mouse = NSEvent.mouseLocation
        let mouseScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        var origin: CGPoint
        let bounds: NSRect
        if let topLeft = savedTopLeft,
           let screen = NSScreen.screens.first(where: { $0.visibleFrame.insetBy(dx: -20, dy: -20).contains(topLeft) }) {
            bounds = screen.visibleFrame
            origin = CGPoint(x: topLeft.x, y: topLeft.y - size.height)
        } else {
            guard let visible = mouseScreen?.visibleFrame else { return }
            bounds = visible
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        }
        origin.x = max(bounds.minX, min(origin.x, bounds.maxX - size.width))
        origin.y = max(bounds.minY, min(origin.y, bounds.maxY - size.height))
        setFrame(NSRect(origin: origin, size: size))
    }

    /// 中身の高さが変わった(タブを切り替えた・一覧が伸びた)。上端を固定して伸び縮みする
    private func fit(_ size: CGSize) {
        guard panel.isVisible, size.width > 0, size.height > 0, panel.frame.size != size else { return }
        let frame = panel.frame
        var origin = CGPoint(x: frame.minX, y: frame.maxY - size.height)
        if let visible = panel.screen?.visibleFrame {
            origin.y = max(visible.minY, origin.y)
        }
        setFrame(NSRect(origin: origin, size: size))
    }

    private func setFrame(_ frame: NSRect) {
        programmaticMove = true
        panel.setFrame(frame, display: true)
        programmaticMove = false
    }

    func windowDidMove(_ notification: Notification) {
        guard !programmaticMove, panel.isVisible else { return }
        savedTopLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }

    // MARK: 外を押したら閉じる・Esc で閉じる

    private func installMonitors() {
        removeMonitors()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // ほかのアプリを押した
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }) {
            monitors.append(global)
        }
        // 自分の窓の外を押した(小窓・設定・状態バー以外)。Esc で閉じる
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown), handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53, event.window === self.panel {   // Esc
                    Task { @MainActor in self.hide() }
                    return nil
                }
                return event
            }
            if event.window !== self.panel, event.window !== self.ignoredWindow {
                Task { @MainActor in self.hide() }
            }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}

/// アプリをアクティブにしないまま key になれる(文字入力・ショートカット用)
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 窓の中身。角を丸め、自分の大きさを窓に知らせる
private struct PanelRoot: View {
    let coordinator: AppCoordinator
    let sizeChanged: (CGSize) -> Void

    var body: some View {
        MenuContentView(coordinator: coordinator)
            .background(GeometryReader { geo in
                Color.clear.preference(key: PanelSizeKey.self, value: geo.size)
            })
            .onPreferenceChange(PanelSizeKey.self) { sizeChanged($0) }
    }
}

private struct PanelSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
