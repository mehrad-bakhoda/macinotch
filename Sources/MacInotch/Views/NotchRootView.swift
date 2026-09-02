import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    @EnvironmentObject var state: NotchState
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var themes = ThemeManager.shared
    @ObservedObject private var timer = TimerService.shared

    private var t: Theme { themes.theme }
    private var size: CGSize { state.currentSize }

    private var radius: CGFloat {
        state.mode == .collapsed && !state.isLive ? hardwareRadius
                                                  : CGFloat(prefs.d.cornerRadius)
    }

    private var hardwareRadius: CGFloat { 11 }

    var body: some View {
        ZStack(alignment: .top) {
            measuringLayer
            notch
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onPreferenceChange(PanelHeightKey.self) { h in
            guard h > 0 else { return }
            Task { @MainActor in state.measuredExpandedHeight = h }
        }
    }

    @ObservedObject private var strip = ControlStrip.shared
    @ObservedObject private var recorder = MeetingRecorder.shared

    private var shape: NotchShape {
        NotchShape(bottomRadius: radius,
                   topRadius: state.mode == .collapsed ? 7 : 9,
                   bandWidth: usesChin ? state.notchSize.width : 0,
                   bandHeight: usesChin ? state.notchSize.height : 0)
    }

    private var usesChin: Bool {
        state.mode == .collapsed && state.isLive && state.usesChin
    }

    private struct AmbientSignal {
        var color: Color
        var pulses: Bool
    }

    private var ambientSignal: AmbientSignal? {
        let p = prefs.d
        guard p.ambientGlow else { return nil }
        guard AmbientClock.shared.stillFresh(p.ambientTimeout) else { return nil }

        func tint(_ hex: String, _ fallback: Color) -> Color {
            Color(hex: hex) ?? fallback
        }

        if p.ambientOnRecord && MeetingRecorder.shared.recording {
            AmbientClock.shared.note("record")
            return AmbientSignal(color: tint(p.ambientColorRecord, t.red), pulses: true)
        }
        if p.ambientOnFailure && !GitHubService.shared.snapshot.failures.isEmpty {
            AmbientClock.shared.note("failure")
            return AmbientSignal(color: tint(p.ambientColorFailure, t.red), pulses: false)
        }
        if p.ambientOnLimit, let limits = state.usage.codexLimits,
           limits.primary.usedPercent >= 80 {
            AmbientClock.shared.note("limit-\(Int(limits.primary.usedPercent / 5))")
            if limits.primary.usedPercent >= 95 {
                return AmbientSignal(color: tint(p.ambientColorFailure, t.red),
                                     pulses: false)
            }
            return AmbientSignal(color: tint(p.ambientColorLimit, t.orange),
                                 pulses: false)
        }
        if p.ambientOnWaiting && state.hasAttention {
            AmbientClock.shared.note("waiting")
            return AmbientSignal(color: tint(p.ambientColorWaiting, t.accent),
                                 pulses: true)
        }
        return nil
    }

    @ViewBuilder
    private func ambientStroke(_ signal: AmbientSignal, _ level: Double) -> some View {
        let width = prefs.d.ambientWidth
        let style = prefs.d.ambientStyle

        switch style {
        case "hairline":
            shape.stroke(signal.color.opacity(level), lineWidth: width)

        case "sweep":
            shape.stroke(
                AngularGradient(
                    colors: [signal.color.opacity(level * 0.12),
                             signal.color.opacity(level),
                             signal.color.opacity(level * 0.45),
                             signal.color.opacity(level),
                             signal.color.opacity(level * 0.12)],
                    center: .center),
                lineWidth: width)

        default:
            ZStack {
                shape.stroke(signal.color.opacity(level * 0.55),
                             lineWidth: width * 3.2)
                    .blur(radius: width * 2.4)
                shape.stroke(signal.color.opacity(level * 0.85),
                             lineWidth: width * 1.6)
                    .blur(radius: width * 0.7)
                shape.stroke(
                    LinearGradient(
                        colors: [signal.color.opacity(level),
                                 signal.color.opacity(level * 0.5),
                                 signal.color.opacity(level * 0.95)],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: width)
            }
        }
    }

    @ViewBuilder private var ambientGlow: some View {
        if let signal = ambientSignal {
            let base = prefs.d.ambientIntensity
            if signal.pulses {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { line in
                    let phase = line.date.timeIntervalSinceReferenceDate
                        * max(0.2, prefs.d.ambientSpeed)
                    let eased = pow(0.5 + 0.5 * sin(phase * 1.7), 1.8)
                    ambientStroke(signal, base * (0.35 + 0.65 * eased))
                }
                .allowsHitTesting(false)
            } else {
                ambientStroke(signal, base)
                    .allowsHitTesting(false)
            }
        }
    }

    private var stripReadout: some View {
        Group {
            if strip.showing, let target = strip.lastTarget {
                VStack(spacing: 5) {
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Image(systemName: target.symbol)
                            .font(.system(size: 10, weight: .semibold))
                        Capsule()
                            .fill(t.wellFill)
                            .frame(width: 92, height: 3)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(t.accent)
                                    .frame(width: max(3, 92 * strip.value), height: 3)
                            }
                        Text("\(Int(strip.value * 100))")
                            .font(.system(size: 9.5, weight: .semibold))
                            .monospacedDigit()
                            .frame(width: 22, alignment: .trailing)
                    }
                    .foregroundStyle(t.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(t.control))
                    .padding(.bottom, 6)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: strip.showing)
    }

    private var notch: some View {
        ZStack(alignment: .top) {
            PanelSurface(shape: shape, theme: t, glass: prefs.d.glassEnabled)
            innerGlow

            if state.hasRealNotch {
                NotchShape(bottomRadius: hardwareRadius, topRadius: 0)
                    .fill(Color.black)
                    .frame(width: state.notchSize.width, height: state.notchSize.height)
                    .allowsHitTesting(false)
            }

            contentLayer
        }
        .frame(width: size.width, height: size.height)

        .clipShape(shape)
        .overlay(rim)
        .overlay(attentionGlow)
        .overlay(ambientGlow)
        .overlay(stripReadout)
        .overlay(dropHighlight)
        .overlay(alignment: .bottom) { edgeProgress }
        .overlay { timerRing }
        .compositingGroup()
        .shadow(color: .black.opacity(state.mode == .collapsed ? 0.22 : 0.38),
                radius: state.mode == .collapsed ? 10 : 30, y: state.mode == .collapsed ? 5 : 14)
        .shadow(color: .black.opacity(state.mode == .collapsed ? 0.10 : 0.18),
                radius: state.mode == .collapsed ? 2 : 5, y: 1)
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    guard prefs.d.stripEnabled else { return }
                    if strip.active == nil {
                        strip.begin(strip.target(for: NSEvent.modifierFlags))
                    }
                    strip.drag(Double(value.translation.width),
                               width: Double(size.width) * 0.55)
                }
                .onEnded { _ in strip.end() }
        )
        .animation(motion, value: state.mode)
        .animation(motion, value: state.isLive)
        .animation(motion, value: size)
        .contentShape(shape)
        .onTapGesture {
            guard state.mode != .collapsed || state.pinned else { return }
            state.togglePin()
        }
        .onDrop(of: [UTType.fileURL], isTargeted: dropTarget) { providers in
            guard prefs.d.shelfEnabled else { return false }
            return ShelfStore.shared.accept(providers)
        }
    }

    private var dropTarget: Binding<Bool> {
        Binding(
            get: { ShelfStore.shared.targeted },
            set: { hovering in
                ShelfStore.shared.targeted = hovering
                guard prefs.d.shelfEnabled else { return }
                if hovering {
                    state.panelTab = .dock
                    state.setHover(true)
                }
            }
        )
    }

    private var contentLayer: some View {
        Group {
            switch state.mode {
            case .collapsed: LiveStrip()
            case .peek:      PeekBanner()
            case .expanded:  ExpandedPanel()
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .animation(nil, value: size)
        .id(state.mode)
        .transition(contentTransition)
    }

    private var contentTransition: AnyTransition {
        guard !prefs.d.reduceMotion else {
            return .asymmetric(
                insertion: .opacity.animation(.easeOut(duration: 0.12)),
                removal: .opacity.animation(.easeIn(duration: 0.08)))
        }
        let style = prefs.d.openAnimation
        let entering = AnyTransition
            .opacity
            .combined(with: .offset(y: -style.contentRise))
            .combined(with: .scale(scale: style.contentScale, anchor: .top))

        return .asymmetric(
            insertion: entering.animation(
                .spring(duration: 0.34, bounce: 0.18).delay(style.openDelay)),
            removal: .opacity.animation(.easeIn(duration: 0.09)))
    }

    private var isOpening: Bool { state.mode != .collapsed }

    private var motion: Animation {
        guard !prefs.d.reduceMotion else { return .easeInOut(duration: 0.18) }
        let style = prefs.d.openAnimation
        return isOpening ? style.opening : style.closing
    }

    @ViewBuilder private var innerGlow: some View {
        if state.mode != .collapsed {
            shape
                .fill(
                    LinearGradient(
                        colors: t.isDark
                            ? [Color.white.opacity(0.07), Color.clear]
                            : [Color.white.opacity(0.35), Color.clear],
                        startPoint: .top, endPoint: .center)
                )
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var rim: some View {
        if state.mode != .collapsed || state.isLive {
            shape.stroke(
                LinearGradient(
                    colors: t.isDark
                        ? [.white.opacity(0.28), .white.opacity(0.06), .white.opacity(0.14)]
                        : [.white.opacity(0.95), .white.opacity(0.20), .black.opacity(0.08)],
                    startPoint: .top, endPoint: .bottom),
                lineWidth: 0.8)
        }
    }

    @ViewBuilder private var attentionGlow: some View {
        if state.hasAttention {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0,
                                    paused: prefs.d.reduceMotion)) { ctx in
                let pulse = (sin(ctx.date.timeIntervalSinceReferenceDate * 2.4) + 1) / 2
                shape
                    .stroke(t.orange.opacity(0.30 + 0.45 * pulse), lineWidth: 1.3)
                    .shadow(color: t.orange.opacity(0.30 + 0.30 * pulse), radius: 9 + 7 * pulse)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var timerRing: some View {
        if timer.isRunning {
            shape
                .trim(from: 0, to: max(0.002, 1 - timer.fraction))
                .stroke(timer.tint.opacity(timer.paused ? 0.35 : 0.9),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .animation(.linear(duration: 0.3), value: timer.fraction)
                .shadow(color: timer.tint.opacity(0.45), radius: 5)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var edgeProgress: some View {
        if state.mode == .collapsed, let item = state.activeProgress {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(item.accent(t).opacity(0.18))
                    Capsule()
                        .fill(item.accent(t))
                        .frame(width: max(3, geo.size.width
                                          * min(max(item.progress ?? 0.05, 0), 1)))
                        .animation(.easeOut(duration: 0.4), value: item.progress ?? 0)
                }
            }
            .frame(height: 2.5)
            .padding(.horizontal, radius * 0.7)
            .padding(.bottom, 2)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var dropHighlight: some View {
        if ShelfStore.shared.targeted {
            shape
                .stroke(t.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .shadow(color: t.accent.opacity(0.5), radius: 12)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var content: some View {
        switch state.mode {
        case .collapsed:
            LiveStrip().transition(.opacity)
        case .peek:
            PeekBanner().transition(.opacity.combined(with: .move(edge: .top)))
        case .expanded:
            ExpandedPanel().transition(.opacity)
        }
    }

    private var measuringLayer: some View {
        ExpandedPanel()
            .environmentObject(state)
            .frame(width: CGFloat(prefs.d.expandedWidth))
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: PanelHeightKey.self, value: geo.size.height)
                }
            )
            .frame(width: 0, height: 0)
            .clipped()
            .hidden()
    }
}

struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let n = nextValue()
        if n > 0 { value = n }
    }
}
