import Cocoa

// デバッグ用: 検出したウィンドウ一覧を表示して終了
if CommandLine.arguments.contains("--list") {
    guard AXIsProcessTrusted() else {
        FileHandle.standardError.write("アクセシビリティ権限がありません\n".data(using: .utf8)!)
        exit(1)
    }
    for (i, w) in WindowManager.listWindows().enumerated() {
        var flags: [String] = []
        if w.isMinimized { flags.append("min") }
        if w.app.isHidden { flags.append("hidden") }
        print(String(format: "%2d", i), w.appName, "|", w.title, "|", w.windowID, flags.joined(separator: ","))
    }
    exit(0)
}

// デバッグ用: ダミーデータでパネルを 5 秒間表示して終了（アクセシビリティ権限は不要）
if CommandLine.arguments.contains("--demo") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let panel = SwitcherPanel()
    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    var demo: [WindowInfo] = []
    for (i, a) in apps.prefix(8).enumerated() {
        let el = AXUIElementCreateApplication(a.processIdentifier)
        demo.append(WindowInfo(app: a, element: el, title: "ダミーウィンドウ \(i + 1) — \(a.localizedName ?? "")", windowID: 0, isMinimized: i == 3))
    }
    panel.show(windows: demo, selected: 1, modifier: Switcher.modifier)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        // --demo-out <path> が指定されていればパネルの見た目を PNG に書き出す
        if let i = CommandLine.arguments.firstIndex(of: "--demo-out"), i + 1 < CommandLine.arguments.count,
           let view = panel.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
    app.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
