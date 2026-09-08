import Cocoa
import ApplicationServices

// AXUIElement(ウィンドウ) から CGWindowID を取得する非公開 API。
// AltTab など多くのウィンドウスイッチャーが使用している安定した関数。
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

// SkyLight (WindowServer クライアント) の非公開 API。特定ウィンドウを指定してアプリを前面化できる。
@_silgen_name("_SLPSSetFrontProcessWithOptions")
private func _SLPSSetFrontProcessWithOptions(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ windowID: CGWindowID, _ mode: UInt32) -> CGError
@_silgen_name("SLPSPostEventRecordTo")
private func SLPSPostEventRecordTo(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError
private let kSLPSUserGenerated: UInt32 = 0x200
// Swift からは GetProcessForPID が「使用不可」扱いなので、シンボル名で直接呼ぶ
@_silgen_name("GetProcessForPID")
private func _GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

struct WindowInfo {
    let app: NSRunningApplication
    let element: AXUIElement
    let title: String
    let windowID: CGWindowID
    let isMinimized: Bool

    var appName: String { app.localizedName ?? "?" }
    var displayTitle: String { title.isEmpty ? appName : title }
}

enum WindowManager {
    private static func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    /// 画面上に表示中のウィンドウを前面から順に並べた順序表 (windowID -> 順位)
    private static func zOrder() -> [CGWindowID: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var order: [CGWindowID: Int] = [:]
        var rank = 0
        for entry in list {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = entry[kCGWindowNumber as String] as? Int else { continue }
            let id = CGWindowID(number)
            if order[id] == nil {
                order[id] = rank
                rank += 1
            }
        }
        return order
    }

    /// 全アプリのウィンドウを「最近使った順(前面順)」で列挙する。
    /// 画面上のウィンドウ → 他の Space / 非表示アプリのウィンドウ → 最小化されたウィンドウ の順。
    static func listWindows() -> [WindowInfo] {
        let order = zOrder()
        var candidates: [(key: Int, info: WindowInfo)] = []
        var sequence = 0

        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != getpid()
        }

        for app in apps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            // 応答しないアプリで固まらないようにタイムアウトを短くする
            AXUIElementSetMessagingTimeout(axApp, 0.3)
            guard let windows = attr(axApp, kAXWindowsAttribute) as? [AXUIElement] else { continue }

            for window in windows {
                let subrole = (attr(window, kAXSubroleAttribute) as? String) ?? ""
                guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }

                var windowID: CGWindowID = 0
                _ = _AXUIElementGetWindow(window, &windowID)
                let title = (attr(window, kAXTitleAttribute) as? String) ?? ""
                let minimized = (attr(window, kAXMinimizedAttribute) as? Bool) ?? false
                let z = order[windowID]

                // 画面外・非最小化・無題 のウィンドウは補助的なものが多いので除外
                if z == nil && !minimized && title.isEmpty { continue }

                let key: Int
                if let z = z {
                    key = z
                } else if minimized {
                    key = 2_000_000 + sequence
                } else {
                    key = 1_000_000 + sequence
                }
                sequence += 1

                candidates.append((key, WindowInfo(app: app, element: window, title: title, windowID: windowID, isMinimized: minimized)))
            }
        }

        return candidates.sorted { $0.key < $1.key }.map { $0.info }
    }

    /// 指定ウィンドウを前面に出してフォーカスする
    static func focus(_ window: WindowInfo) {
        if window.isMinimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        if window.app.isHidden {
            window.app.unhide()
        }

        // 1. SkyLight の非公開 API で「このウィンドウを前面にしてアプリをアクティブ化」する。
        //    macOS 14 以降、バックグラウンドアプリからの NSRunningApplication.activate() は
        //    拒否されることがあるため、こちらを主経路にする（AltTab / yabai と同じ手法）。
        var psn = ProcessSerialNumber()
        if _GetProcessForPID(window.app.processIdentifier, &psn) == noErr {
            _ = _SLPSSetFrontProcessWithOptions(&psn, window.windowID, kSLPSUserGenerated)
            makeKeyWindow(&psn, window.windowID)
        }

        // 2. Accessibility API でウィンドウを前面化
        raise(window)

        // 3. 公開 API でのアクティブ化も念のため実行（失敗しても害はない）
        if #available(macOS 14.0, *) {
            window.app.activate()
        } else {
            window.app.activate(options: [.activateIgnoringOtherApps])
        }

        // アクティブ化と競合することがあるので、少し遅らせてもう一度前面化する
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            raise(window)
        }
    }

    private static func raise(_ window: WindowInfo) {
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    /// 対象ウィンドウをキーウィンドウにするための合成イベントを送る（AltTab 由来の手法）
    private static func makeKeyWindow(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ windowID: CGWindowID) {
        var wid = windowID
        for eventKind: UInt8 in [0x01, 0x02] {
            var bytes = [UInt8](repeating: 0, count: 0xf8)
            bytes[0x04] = 0xF8
            bytes[0x08] = eventKind
            bytes[0x3a] = 0x10
            memset(&bytes[0x20], 0xFF, 0x10)
            memcpy(&bytes[0x3c], &wid, MemoryLayout<UInt32>.size)
            _ = SLPSPostEventRecordTo(psn, &bytes)
        }
    }
}
