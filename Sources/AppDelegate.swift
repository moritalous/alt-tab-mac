import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        NSLog("AltTabMac launched, accessibility trusted=%d", AXIsProcessTrusted() ? 1 : 0)
        if AXIsProcessTrustedWithOptions(options) {
            startSwitcher()
        } else {
            // アクセシビリティ許可が付与されるまで待ち、付与されたら再起動なしで開始する
            trustTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                NSLog("AltTabMac accessibility granted while running")
                self?.startSwitcher()
            }
        }
    }

    private func startSwitcher() {
        let ok = Switcher.shared.start()
        NSLog("AltTabMac event tap start: %@", ok ? "OK" : "FAILED")
        if !ok {
            let alert = NSAlert()
            alert.messageText = "キーボード監視を開始できませんでした"
            alert.informativeText = "システム設定 > プライバシーとセキュリティ > アクセシビリティ で AltTabMac を許可してから、アプリを再起動してください。"
            alert.runModal()
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "\(Switcher.modifier.symbol)⇥"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let trusted = AXIsProcessTrusted()
        let status = menu.addItem(
            withTitle: trusted ? "アクセシビリティ: 許可済み" : "アクセシビリティ: 未許可 (クリックで設定を開く)",
            action: #selector(openAccessibilitySettings), keyEquivalent: "")
        status.target = self

        let running = menu.addItem(
            withTitle: Switcher.shared.isRunning ? "状態: 動作中" : "状態: 停止中 (許可待ち)",
            action: nil, keyEquivalent: "")
        running.isEnabled = false

        menu.addItem(.separator())

        let modifierMenu = NSMenu()
        for modifier in Switcher.Modifier.allCases {
            let item = NSMenuItem(title: "\(modifier.label) + Tab", action: #selector(setModifier(_:)), keyEquivalent: "")
            item.representedObject = modifier.rawValue
            item.state = modifier == Switcher.modifier ? .on : .off
            item.target = self
            modifierMenu.addItem(item)
        }
        let modifierItem = menu.addItem(withTitle: "ショートカット", action: nil, keyEquivalent: "")
        modifierItem.submenu = modifierMenu

        let login = menu.addItem(withTitle: "ログイン時に起動", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.target = self

        menu.addItem(.separator())
        menu.addItem(withTitle: "AltTabMac を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func setModifier(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let modifier = Switcher.Modifier(rawValue: raw) else { return }
        Switcher.modifier = modifier
        statusItem.button?.title = "\(modifier.symbol)⇥"
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "ログイン時起動の設定に失敗しました"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
