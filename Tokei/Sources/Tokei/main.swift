import AppKit
import SwiftUI
import Combine

final class Store: ObservableObject {
    @Published var usage: Usage?
    @Published var lastUpdated: String = "加载中…"
    @Published var peers: [PeerDevice] = []
    @Published var syncing = false

    let syncManager = SyncManager()
    var autoSyncTimer: Timer?

    @AppStorage("showAllDevices") var showAllDevices = true
    @AppStorage("syncEnabled") var syncEnabled = false

    func refresh() {
        DataLoader.load { [weak self] u in
            guard let self = self else { return }
            guard var local = u else { return }
            if self.syncEnabled && self.showAllDevices {
                let p = self.syncManager.loadPeers()
                self.peers = p
                if !p.isEmpty { local = SyncManager.merge(local: local, peers: p) }
            } else {
                self.peers = []
            }
            self.usage = local
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            self.lastUpdated = "更新 " + f.string(from: Date())
            (NSApp.delegate as? AppDelegate)?.updateStatusTitle()
        }
    }

    func doSync() {
        syncing = true
        syncManager.gitSync { [weak self] ok in
            self?.syncing = false
            if ok { self?.refresh() }
        }
    }

    func startAutoSync(minutes: Int) {
        stopAutoSync()
        autoSyncTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60),
                                             repeats: true) { [weak self] _ in self?.doSync() }
    }

    func stopAutoSync() {
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var statusItem: NSStatusItem!
    var popover = NSPopover()
    var timer: Timer?

    // 菜单栏家族品牌色(与面板 Theme.claude/codex 一致)。
    static let claudeColor = NSColor(red: 0.92, green: 0.52, blue: 0.40, alpha: 1)
    static let codexColor  = NSColor(red: 0.42, green: 0.68, blue: 0.98, alpha: 1)

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.action = #selector(togglePopover)
            b.target = self
        }
        updateStatusTitle()

        let host = NSHostingController(rootView: PanelView(store: store))
        let vc = NSViewController()
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false
        host.view.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host.view)
        let container = NSView()
        container.addSubview(effect)
        vc.view = container
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effect.topAnchor.constraint(equalTo: container.topAnchor),
            effect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: effect.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        popover.contentViewController = vc
        popover.behavior = .transient
        popover.animates = true

        store.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.store.refresh()
        }

        if CommandLine.arguments.contains("--autoshow") {
            popover.behavior = .applicationDefined
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.togglePopover()
            }
        }
    }

    func updateStatusTitle() {
        guard let b = statusItem?.button else { return }
        let s = NSMutableAttributedString()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

        // 一格 = 时钟图标 + 5h 剩余%,按家族品牌色着色(橙=Claude 青=Codex)。
        func seg(_ value: String, _ color: NSColor) {
            if s.length > 0 {
                s.append(NSAttributedString(string: "  ", attributes: [.font: font]))
            }
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            let img = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg)
            img?.isTemplate = false
            let att = NSTextAttachment(); att.image = img
            s.append(NSAttributedString(attachment: att))
            s.append(NSAttributedString(string: " " + value,
                attributes: [.font: font, .baselineOffset: 1, .foregroundColor: color]))
        }

        if let u = store.usage {
            if let q5 = u.claude.q5 { seg(String(format: "%.0f", 100 - q5), Self.claudeColor) }
            if let p5 = u.codex.p5 { seg(String(format: "%.0f", 100 - p5), Self.codexColor) }
            if s.length == 0 { seg("—", .secondaryLabelColor) }   // 两家额度都暂缺
        } else {
            seg("…", .secondaryLabelColor)                        // 加载中
        }
        b.attributedTitle = s
        b.image = nil
    }

    @objc func togglePopover() {
        guard let b = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.refresh()
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.resizePopover()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.resizePopover()
            }
        }
    }

    func resizePopover() {
        guard popover.isShown else { return }
        popover.contentViewController?.view.needsLayout = true
        popover.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = popover.contentViewController?.view.fittingSize ?? .zero
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let capped = NSSize(width: size.width, height: min(size.height, screen.height - 60))
        if capped.width > 0 && capped.height > 0 {
            popover.contentSize = capped
        }
    }
}

// 离屏截图模式:Tokei --shot /path/out.png
enum Shot {
    static func run(path: String) {
        _ = NSApplication.shared
        var usage: Usage?
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { usage = DataLoader.loadSync(); sem.signal() }
        sem.wait()
        MainActor.assumeIsolated {
            let store = Store()
            store.usage = usage
            store.lastUpdated = "预览"
            let content = PanelView(store: store, scrollable: false)
                .background(Color(red: 0.22, green: 0.23, blue: 0.26))
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            if let cg = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: cg)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
            }
        }
        exit(0)
    }
}

if let idx = CommandLine.arguments.firstIndex(of: "--shot") {
    let out = CommandLine.arguments.count > idx + 1
        ? CommandLine.arguments[idx + 1] : "/tmp/tokei_shot.png"
    Shot.run(path: out)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
