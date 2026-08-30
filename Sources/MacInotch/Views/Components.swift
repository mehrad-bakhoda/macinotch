import SwiftUI

struct PanelSurface<S: Shape>: View {
    var shape: S
    var theme: Theme
    var glass: Bool

    var body: some View {
        if glass {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular.tint(theme.panelTint), in: shape)
            } else {
                material
            }
            #else
            material
            #endif
        } else {
            shape.fill(theme.isDark ? Color(white: 0.05) : Color(white: 0.97))
        }
    }

    private var material: some View {
        shape
            .fill(theme.isDark ? AnyShapeStyle(.ultraThinMaterial)
                               : AnyShapeStyle(.regularMaterial))
            .overlay(shape.fill(theme.panelTint))
    }
}

struct Card<Content: View>: View {
    var theme: Theme
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.raised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(theme.raisedStroke, lineWidth: 0.5)
                    )
            )
    }
}

struct StatRing: View {
    var value: Double
    var label: String
    var readout: String
    var unit: String = ""
    var tint: Color
    var theme: Theme
    var size: CGFloat = 42

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(theme.wellFill, lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: max(0.001, min(value, 1)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.55), value: value)

                HStack(alignment: .firstTextBaseline, spacing: 0.5) {
                    Text(readout)
                        .font(.system(size: size * 0.29, weight: .semibold, design: .rounded))
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: size * 0.18, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.tertiary)
                    }
                }
                .foregroundStyle(theme.primary)
                .monospacedDigit()
            }
            .frame(width: size, height: size)

            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.tertiary)
                .textCase(.uppercase)
                .kerning(0.4)
        }
    }
}

struct MeterRow: View {
    var title: String
    var detail: String
    var value: Double
    var tint: Color
    var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.secondary)
                Spacer(minLength: 4)
                Text(detail)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.primary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.wellFill)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(3, geo.size.width * min(max(value, 0), 1)))
                        .animation(.easeOut(duration: 0.5), value: value)
                }
            }
            .frame(height: 4)
        }
    }
}

struct ProgressBar: View {
    var value: Double?
    var tint: Color
    var theme: Theme
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.wellFill)
                if let value {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(2, geo.size.width * min(max(value, 0), 1)))
                        .animation(.easeOut(duration: 0.4), value: value)
                } else {
                    IndeterminateBar(tint: tint, width: geo.size.width)
                }
            }
        }
        .frame(height: height)
    }
}

private struct IndeterminateBar: View {
    var tint: Color
    var width: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let span = width * 0.35
            let travel = (sin(t * 1.6) + 1) / 2
            Capsule().fill(tint).frame(width: span)
                .offset(x: travel * (width - span))
        }
    }
}

struct Visualizer: View {
    var tint: Color
    var active: Bool
    var bars: Int = 4
    var barWidth: CGFloat = 2.5
    var maxHeight: CGFloat = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barWidth) {
                ForEach(0..<bars, id: \.self) { i in
                    Capsule().fill(tint).frame(width: barWidth, height: height(i, t))
                }
            }
            .frame(height: maxHeight)
        }
    }

    private func height(_ i: Int, _ t: Double) -> CGFloat {
        guard active else { return barWidth }

        let phase = Double(i) * 0.9
        let n = (sin(t * 5.1 + phase) * 0.6 + sin(t * 3.3 + phase * 1.7) * 0.4 + 1) / 2
        return max(barWidth, maxHeight * (0.22 + 0.78 * n))
    }
}

struct Artwork: View {
    var image: NSImage?
    var tint: Color
    var side: CGFloat
    var radius: CGFloat = 8

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [tint.opacity(0.7), tint.opacity(0.25)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: side * 0.4, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    )
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
    }
}

struct SourceGlyph: View {
    var source: NotchSource
    var kind: NotchKind
    var theme: Theme
    var side: CGFloat = 26

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.32, style: .continuous)
                .fill(color.opacity(theme.isDark ? 0.22 : 0.16))
            RoundedRectangle(cornerRadius: side * 0.32, style: .continuous)
                .strokeBorder(color.opacity(0.35), lineWidth: 0.5)
            Image(systemName: glyph)
                .font(.system(size: side * 0.46, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: side, height: side)
    }

    private var color: Color { source.tint(theme) }

    private var glyph: String {
        switch source {
        case .claude:  return "sparkle"
        case .chatgpt: return "bubble.left.and.bubble.right.fill"
        case .spotify: return "music.note"
        case .system:  return "gearshape.fill"
        case .custom:  return kind.symbol
        }
    }
}

struct PresenceChip: View {
    var source: NotchSource
    var running: Bool
    var theme: Theme
    var side: CGFloat = 18

    var body: some View {
        SourceIcon(source: source, kind: .info, theme: theme,
                   side: side, muted: !running)
            .overlay(alignment: .bottomTrailing) {
                if running {
                    Circle()
                        .fill(theme.green)
                        .frame(width: side * 0.3, height: side * 0.3)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.35),
                                                       lineWidth: 0.5))
                        .offset(x: 1, y: 1)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: running)
            .help("\(source.displayName): \(running ? "running" : "not running")")
    }
}

struct Sparkline: View {
    var values: [Double]
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            if values.count > 1 {
                let w = geo.size.width, h = geo.size.height
                let step = w / CGFloat(values.count - 1)

                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    for (i, v) in values.enumerated() {
                        p.addLine(to: CGPoint(x: CGFloat(i) * step, y: h - CGFloat(v) * h))
                    }
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))

                Path { p in
                    for (i, v) in values.enumerated() {
                        let point = CGPoint(x: CGFloat(i) * step, y: h - CGFloat(v) * h)
                        if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                    }
                }
                .stroke(tint.opacity(0.85), style: StrokeStyle(lineWidth: 1,
                                                               lineJoin: .round))
            }
        }
    }
}

@MainActor
final class HoverTracker: ObservableObject {
    static let shared = HoverTracker()
    @Published var hovered: String?
}

struct SurfaceCard<Content: View>: View {
    var theme: Theme
    var padding: CGFloat = 14
    var radius: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(theme.cardGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(theme.cardStroke, lineWidth: 0.75)
                    )
            )
    }
}

struct PanelRow<Leading: View, Trailing: View>: View {
    var id: String
    var title: String
    var subtitle: String?
    var theme: Theme
    var onTap: (() -> Void)?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @ObservedObject private var hover = HoverTracker.shared

    private var isHovered: Bool { hover.hovered == id }

    var body: some View {
        HStack(spacing: 11) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.primary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? theme.control : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { inside in
            if inside { hover.hovered = id }
            else if hover.hovered == id { hover.hovered = nil }
        }
        .onTapGesture { onTap?() }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

struct IconBadge: View {
    var symbol: String
    var tint: Color
    var theme: Theme
    var side: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.30, style: .continuous)
                .fill(tint.opacity(theme.isDark ? 0.20 : 0.14))
            Image(systemName: symbol)
                .font(.system(size: side * 0.44, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: side, height: side)
    }
}

struct PillButton: View {
    var label: String
    var tint: Color
    var theme: Theme
    var filled: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            SoundKit.tap()
            action()
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(filled ? Color.white : tint)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(filled ? tint : tint.opacity(theme.isDark ? 0.18 : 0.13))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct VitalColumn: View {
    var label: String
    var value: String
    var unit: String
    var detail: String
    var fraction: Double
    var tint: Color
    var theme: Theme
    var history: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(theme.tertiary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.primary)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.tertiary)
            }
            .fixedSize()
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.3), value: value)

            ZStack(alignment: .bottomLeading) {
                if !history.isEmpty {
                    Sparkline(values: history, tint: tint)
                        .frame(height: 14)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.wellFill)
                        Capsule().fill(tint)
                            .frame(width: max(2, geo.size.width
                                              * min(max(fraction, 0), 1)))
                            .animation(.easeOut(duration: 0.5), value: fraction)
                    }
                    .frame(height: 2.5)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 14)

            Text(detail)
                .font(.system(size: 9.5))
                .foregroundStyle(theme.tertiary)
                .lineLimit(1)
                .opacity(detail.isEmpty ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
