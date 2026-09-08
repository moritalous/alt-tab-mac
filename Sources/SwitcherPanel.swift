import Cocoa

/// ウィンドウ一覧を表示するオーバーレイパネル（フォーカスを奪わない）
final class SwitcherPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate {
    private var items: [WindowInfo] = []
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let footer = NSTextField(labelWithString: "")

    private let panelWidth: CGFloat = 720
    private let rowHeight: CGFloat = 52
    private let rowGap: CGFloat = 4
    private let maxVisibleRows = 12
    private let cornerRadius: CGFloat = 16

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 300),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        animationBehavior = .none

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        // layer.cornerRadius だけだとウィンドウの影が四角いまま描かれ、角の外側に影がはみ出す。
        // maskImage で形状そのものを伝えると、ぼかしの範囲も影も角丸に沿う。
        effect.maskImage = Self.roundedMask(radius: cornerRadius)
        contentView = effect

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.width = panelWidth - 24
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = rowHeight
        table.intercellSpacing = NSSize(width: 0, height: rowGap)
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.style = .plain
        table.focusRingType = .none
        table.dataSource = self
        table.delegate = self

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(scroll)

        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor
        footer.alignment = .center
        footer.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(footer)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: effect.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
            footer.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            footer.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -10),
        ])
    }

    func show(windows: [WindowInfo], selected: Int, modifier: Switcher.Modifier) {
        items = windows
        table.reloadData()
        footer.stringValue = "\(modifier.symbol) を離す: 切り替え    ⇥ / ⇧⇥ / 矢印: 移動    Esc: キャンセル    (\(windows.count) ウィンドウ)"

        let rows = min(items.count, maxVisibleRows)
        let listHeight = CGFloat(rows) * (rowHeight + rowGap)
        let height = listHeight + 12 + 8 + 16 + 10

        let screen = screenUnderMouse()
        let frame = screen.visibleFrame
        let rect = NSRect(
            x: (frame.midX - panelWidth / 2).rounded(),
            y: (frame.midY - height / 2).rounded(),
            width: panelWidth,
            height: height
        )
        setFrame(rect, display: true)
        invalidateShadow()
        select(selected)
        orderFrontRegardless()
    }

    func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
    }

    func dismiss() {
        orderOut(nil)
        items = []
        table.reloadData()
    }

    /// 角丸のマスク画像。中央を伸縮させるので、どのサイズのパネルにも使い回せる。
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        HighlightRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: WindowCell.identifier, owner: nil) as? WindowCell) ?? WindowCell()
        cell.configure(items[row], index: row)
        return cell
    }
}

/// キーウィンドウでなくてもアクセントカラーで選択行を描画する
private final class HighlightRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
    }
}

private final class WindowCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("WindowCell")

    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let indexLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        indexLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        indexLabel.alignment = .right
        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indexLabel)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 36),
            icon.heightAnchor.constraint(equalToConstant: 36),

            indexLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            indexLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            indexLabel.widthAnchor.constraint(equalToConstant: 30),

            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: indexLabel.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
        ])
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyColors() }
    }

    func configure(_ window: WindowInfo, index: Int) {
        icon.image = window.app.icon
        titleLabel.stringValue = window.displayTitle
        var subtitle = window.appName
        if window.isMinimized { subtitle += "  ·  最小化" }
        if window.app.isHidden { subtitle += "  ·  非表示" }
        subtitleLabel.stringValue = subtitle
        indexLabel.stringValue = "\(index + 1)"
    }

    private func applyColors() {
        let selected = backgroundStyle == .emphasized
        titleLabel.textColor = selected ? .white : .labelColor
        subtitleLabel.textColor = selected ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor
        indexLabel.textColor = selected ? NSColor.white.withAlphaComponent(0.7) : .tertiaryLabelColor
    }
}
