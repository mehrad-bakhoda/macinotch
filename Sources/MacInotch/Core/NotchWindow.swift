import AppKit
import SwiftUI

struct NotchGeometry {
    var screen: NSScreen
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasRealNotch: Bool

    static func detect(preferring target: NSScreen? = nil) -> NotchGeometry {
        let screen = target
            ?? NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main!
        let inset = screen.safeAreaInsets.top

        if inset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let w = screen.frame.width - left.width - right.width
            return NotchGeometry(screen: screen, notchWidth: w,
                                 notchHeight: inset, hasRealNotch: true)
        }

        return NotchGeometry(screen: screen, notchWidth: 190,
                             notchHeight: max(screen.frame.height > 0 ? 32 : 32, 32),
                             hasRealNotch: false)
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchWindowController {

    static let windowSize = CGSize(width: 900, height: 860)

    private(set) var panel: NotchPanel!
    private var geometry: NotchGeometry
    private let state: NotchState
    private var hoverTimer: Timer?
    private var outsideClickMonitor: Any?

    init(state: NotchState) {
        self.state = state
        self.geometry = NotchGeometry.detect()
    }

    func install() {
        let panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none

        let root = NotchRootView()
            .environmentObject(state)
            .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        let host = NSHostingView(rootView: AnyView(root))
        host.frame = NSRect(origin: .zero, size: Self.windowSize)
        panel.contentView = host

        self.panel = panel
        applyGeometry()
        reposition()
        panel.orderFrontRegardless()
        applyAppearance()
        startHoverTracking()

        NotificationCenter.default.addObserver(
            forName: ThemeManager.appearanceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyAppearance() }
        }
        startOutsideClickWatch()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.geometry = NotchGeometry.detect()
                self?.applyGeometry()
                self?.reposition()
            }
        }
    }

    func applyAppearance() {
        switch Prefs.shared.d.appearance {
        case .system: panel.appearance = nil
        case .light:  panel.appearance = NSAppearance(named: .aqua)
        case .dark:   panel.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func applyGeometry() {
        state.notchSize = CGSize(width: geometry.notchWidth, height: geometry.notchHeight)
    }

    private func reposition() {
        let f = geometry.screen.frame
        let origin = NSPoint(x: f.midX - Self.windowSize.width / 2,
                             y: f.maxY - Self.windowSize.height)
        panel.setFrame(NSRect(origin: origin, size: Self.windowSize), display: true)
    }

    private var interactiveRect: NSRect {
        let size = state.currentSize
        let f = geometry.screen.frame

        let pad: CGFloat = state.mode == .collapsed ? 6 : 0
        return NSRect(x: f.midX - size.width / 2 - pad,
                      y: f.maxY - size.height - pad,
                      width: size.width + pad * 2,
                      height: size.height + pad)
    }

    private func startHoverTracking() {

        let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollMouse() }
        }
        RunLoop.main.add(t, forMode: .common)
        hoverTimer = t
    }

    private func followPointerIfNeeded(_ point: NSPoint) {
        guard Prefs.shared.d.followActiveDisplay,
              state.mode == .collapsed, !state.pinned else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              screen !== geometry.screen else { return }
        geometry = NotchGeometry.detect(preferring: screen)
        applyGeometry()
        reposition()
    }

    private func pollMouse() {
        let p = NSEvent.mouseLocation
        followPointerIfNeeded(p)
        let inside = interactiveRect.contains(p)
        if inside != state.hovering { state.setHover(inside) }

        panel.ignoresMouseEvents = !(inside || state.pinned)
    }

    private func startOutsideClickWatch() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state.pinned else { return }
                if !self.interactiveRect.contains(NSEvent.mouseLocation) {
                    self.state.unpin()
                }
            }
        }
    }
}
