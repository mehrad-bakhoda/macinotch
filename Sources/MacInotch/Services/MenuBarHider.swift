import AppKit

@MainActor
final class MenuBarHider: ObservableObject {
    static let shared = MenuBarHider()

    @Published private(set) var hidden = false
    @Published private(set) var installed = false

    private var toggleItem: NSStatusItem?
    private var expanderItem: NSStatusItem?
    private var autoTask: Task<Void, Never>?

    private static let expandedLength: CGFloat = 22
    private static let collapsedLength: CGFloat = 10_000

    private init() {}

    var diagnostics: [String: Any] {
        [
            "expanderLength": Double(expanderItem?.length ?? -1),
            "expanderWidth": Double(expanderItem?.button?.window?.frame.width ?? -1),
            "expanderX": Double(expanderItem?.button?.window?.frame.origin.x ?? -1),
            "toggleX": Double(toggleItem?.button?.window?.frame.origin.x ?? -1),
            "screenWidth": Double(NSScreen.main?.frame.width ?? 0),
        ]
    }

    func install() {
        guard toggleItem == nil else { return }

        let expander = NSStatusBar.system.statusItem(withLength: Self.expandedLength)
        expander.button?.title = ""
        expander.button?.image = Self.separatorImage()
        expander.button?.imagePosition = .imageOnly
        expander.button?.target = self
        expander.button?.action = #selector(toggle)
        expander.autosaveName = "io.macinotch.expander"
        expanderItem = expander

        let toggle = NSStatusBar.system.statusItem(withLength: 24)
        toggle.button?.image = Self.chevronImage(hidden: hidden)
        toggle.button?.target = self
        toggle.button?.action = #selector(self.toggle)
        toggle.autosaveName = "io.macinotch.toggle"
        toggleItem = toggle

        installed = true
        apply()
    }

    func uninstall() {
        autoTask?.cancel()
        if let expanderItem { NSStatusBar.system.removeStatusItem(expanderItem) }
        if let toggleItem { NSStatusBar.system.removeStatusItem(toggleItem) }
        expanderItem = nil
        toggleItem = nil
        installed = false
        hidden = false
    }

    @objc private func toggle() {
        hidden.toggle()
        SoundKit.tap()
        apply()
        scheduleAutoHide()
    }

    func setHidden(_ value: Bool) {
        guard hidden != value else { return }
        hidden = value
        apply()
    }

    private func apply() {
        expanderItem?.length = hidden ? Self.collapsedLength : Self.expandedLength
        toggleItem?.button?.image = Self.chevronImage(hidden: hidden)
        Prefs.shared.d.menuBarHidden = hidden
    }

    private func scheduleAutoHide() {
        autoTask?.cancel()
        guard !hidden, Prefs.shared.d.menuBarAutoHideSeconds > 0 else { return }
        let delay = Prefs.shared.d.menuBarAutoHideSeconds
        autoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.setHidden(true) }
        }
    }

    private static func chevronImage(hidden: Bool) -> NSImage? {
        let name = hidden ? "chevron.compact.left" : "chevron.compact.right"
        let image = NSImage(systemSymbolName: name,
                            accessibilityDescription: "Toggle hidden menu bar items")
        image?.isTemplate = true
        return image
    }

    private static func separatorImage() -> NSImage {
        let size = NSSize(width: 8, height: 14)
        let image = NSImage(size: size, flipped: false) { _ in
            let bar = NSBezierPath(roundedRect: NSRect(x: 3, y: 2, width: 2, height: 10),
                                   xRadius: 1, yRadius: 1)
            NSColor.black.setFill()
            bar.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
