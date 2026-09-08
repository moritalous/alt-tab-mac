import Cocoa

/// キーボードイベントを監視して Alt(Option)+Tab を処理する本体
final class Switcher {
    static let shared = Switcher()

    enum Modifier: String, CaseIterable {
        case option, control, command

        var flag: CGEventFlags {
            switch self {
            case .option: return .maskAlternate
            case .control: return .maskControl
            case .command: return .maskCommand
            }
        }
        var symbol: String {
            switch self {
            case .option: return "⌥"
            case .control: return "⌃"
            case .command: return "⌘"
            }
        }
        var label: String {
            switch self {
            case .option: return "Option (⌥)"
            case .control: return "Control (⌃)"
            case .command: return "Command (⌘)"
            }
        }
    }

    static var modifier: Modifier {
        get { Modifier(rawValue: UserDefaults.standard.string(forKey: "modifier") ?? "") ?? .option }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "modifier") }
    }

    private(set) var isRunning = false
    private var tap: CFMachPort?
    private var active = false
    private var windows: [WindowInfo] = []
    private var selected = 0
    private let panel = SwitcherPanel()

    private enum Key {
        static let tab: Int64 = 48
        static let escape: Int64 = 53
        static let returnKey: Int64 = 36
        static let enter: Int64 = 76
        static let space: Int64 = 49
        static let left: Int64 = 123
        static let right: Int64 = 124
        static let down: Int64 = 125
        static let up: Int64 = 126
    }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                Switcher.shared.handle(type: type, event: event)
            },
            userInfo: nil
        ) else {
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let modifierFlag = Switcher.modifier.flag
        let modifierHeld = flags.contains(modifierFlag)
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .flagsChanged:
            if active && !modifierHeld { commit() }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            if !active {
                let allModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
                let others = allModifiers.subtracting(modifierFlag)
                if keycode == Key.tab && modifierHeld && flags.isDisjoint(with: others) {
                    begin(reverse: flags.contains(.maskShift))
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }
            switch keycode {
            case Key.tab: move(flags.contains(.maskShift) ? -1 : 1)
            case Key.down, Key.right: move(1)
            case Key.up, Key.left: move(-1)
            case Key.escape: cancel()
            case Key.returnKey, Key.enter, Key.space: commit()
            default: break
            }
            return nil

        case .keyUp:
            return active ? nil : Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func begin(reverse: Bool) {
        windows = WindowManager.listWindows()
        NSLog("AltTabMac begin: %d windows", windows.count)
        guard !windows.isEmpty else { return }
        active = true
        // 先頭は現在のウィンドウなので、Windows と同じく「直前のウィンドウ」を初期選択にする
        if windows.count > 1 {
            selected = reverse ? windows.count - 1 : 1
        } else {
            selected = 0
        }
        panel.show(windows: windows, selected: selected, modifier: Switcher.modifier)
    }

    private func move(_ delta: Int) {
        guard !windows.isEmpty else { return }
        selected = (selected + delta + windows.count) % windows.count
        panel.select(selected)
    }

    private func commit() {
        guard active else { return }
        active = false
        panel.dismiss()
        if windows.indices.contains(selected) {
            WindowManager.focus(windows[selected])
        }
        windows = []
    }

    private func cancel() {
        active = false
        panel.dismiss()
        windows = []
    }
}
