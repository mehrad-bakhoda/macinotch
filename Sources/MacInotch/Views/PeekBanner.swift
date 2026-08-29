import SwiftUI

struct PeekBanner: View {
    @EnvironmentObject var state: NotchState
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var themes = ThemeManager.shared

    private var t: Theme { themes.theme }
    private var item: NotchItem? { state.featured }

    var body: some View {
        VStack(spacing: 0) {
            topRow.frame(height: state.notchSize.height)
            bottomRow.frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 7)
    }

    private var sideWidth: CGFloat {
        max(70, (state.peekSize.width - state.notchSize.width - 28) / 2)
    }

    private var topRow: some View {
        HStack(spacing: 0) {
            Group {
                if let item {
                    if item.kind == .music {
                        Artwork(image: item.artwork, tint: item.accent(t),
                                side: state.notchSize.height - 12, radius: 5)
                    } else {
                        SourceIcon(source: item.source, kind: item.kind, theme: t,
                                   side: state.notchSize.height - 12)
                    }
                }
            }
            .frame(width: sideWidth, alignment: .leading)

            Spacer(minLength: state.notchSize.width - 6)

            Group {
                if let item { trailingIndicator(item) }
            }
            .frame(width: sideWidth, alignment: .trailing)
        }
    }

    @ViewBuilder private func trailingIndicator(_ item: NotchItem) -> some View {
        switch item.kind {
        case .music:
            Visualizer(tint: item.accent(t), active: state.music.isPlaying,
                       maxHeight: state.notchSize.height - 18)
        case .progress:
            Text(item.progress.map { "\(Int($0 * 100))%" } ?? "…")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(item.accent(t))
                .monospacedDigit()
        case .attention:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(t.orange)
                .symbolEffect(.pulse)
        default:
            Image(systemName: item.kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(item.accent(t))
        }
    }

    @ViewBuilder private var bottomRow: some View {
        if let item {
            VStack(spacing: 5) {
                HStack(spacing: 7) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(t.primary)
                        .lineLimit(1)

                    if !item.body.isEmpty {
                        Circle()
                            .fill(t.tertiary)
                            .frame(width: 2.5, height: 2.5)
                        Text(item.body)
                            .font(.system(size: 11.5))
                            .foregroundStyle(t.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)

                    Text(item.source.displayName.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .kerning(0.7)
                        .foregroundStyle(item.accent(t))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(item.accent(t).opacity(0.14)))
                }

                if item.kind == .progress {
                    ProgressBar(value: item.progress, tint: item.accent(t), theme: t)
                } else if item.kind == .music, state.music.duration > 0 {
                    ProgressBar(value: state.music.fraction, tint: item.accent(t),
                                theme: t, height: 2.5)
                }
            }
        }
    }
}
