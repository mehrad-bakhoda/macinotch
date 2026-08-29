import SwiftUI

struct LiveStrip: View {
    @EnvironmentObject var state: NotchState
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var themes = ThemeManager.shared
    @ObservedObject private var timer = TimerService.shared
    @ObservedObject private var weather = WeatherService.shared

    private var t: Theme { themes.theme }
    private var p: PrefsData { prefs.d }

    var body: some View {
        if state.usesChin && !state.isIdle && state.isLive {
            chinRow
        } else if state.isIdle {
            idleClock
        } else if state.isLive {
            HStack(spacing: 0) {
                slots(state.leftItems)
                    .frame(width: state.liveSlotWidth, alignment: .leading)
                    .padding(.leading, 12)

                Spacer(minLength: state.notchSize.width)

                slots(state.rightItems)
                    .frame(width: state.liveSlotWidth, alignment: .trailing)
                    .padding(.trailing, 12)
            }
            .frame(height: state.notchSize.height)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var chinRow: some View {
        HStack(spacing: 12) {
            slots(state.leftItems)
            Spacer(minLength: 6)
            slots(state.rightItems)
        }
        .padding(.horizontal, 16)
        .frame(height: NotchState.chinHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var idleClock: some View {
        HStack(spacing: 0) {
            Text(DateKit.clock.string(from: state.now))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(t.primary)
                .monospacedDigit()
                .frame(width: state.liveSlotWidth + 20, alignment: .leading)
                .padding(.leading, 11)

            Spacer(minLength: state.notchSize.width - 6)

            Text(DateKit.gregShort.string(from: state.now))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(t.secondary)
                .frame(width: state.liveSlotWidth + 20, alignment: .trailing)
                .padding(.trailing, 11)
        }
        .frame(height: state.notchSize.height)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func slots(_ items: [PrefsData.StripItem]) -> some View {
        HStack(spacing: 8) {
            ForEach(items) { item in view(for: item) }
        }
    }

    @ViewBuilder
    private func view(for item: PrefsData.StripItem) -> some View {
        switch item {
        case .cpu:
            metric("cpu", "\(Int((state.stats.cpuTotal * 100).rounded()))", "%",
                   t.load(state.stats.cpuTotal))
        case .ram:
            metric("memorychip", "\(Int((state.stats.memPressure * 100).rounded()))", "%",
                   t.load(state.stats.memPressure))
        case .temp:
            if state.temps.available {
                metric("thermometer.medium",
                       Temperatures.format(state.temps.soc, fahrenheit: p.fahrenheit)
                           .replacingOccurrences(of: "°", with: ""),
                       "°", t.load(state.temps.socLoad))
            }
        case .weather:
            if weather.snapshot.available {
                metric(weather.snapshot.symbol,
                       weather.snapshot.formatted(weather.snapshot.temperature,
                                                  fahrenheit: p.weatherFahrenheit)
                           .replacingOccurrences(of: "°", with: ""),
                       "°", t.blue)
            }
        case .battery:
            if state.battery.present {
                metric(state.battery.symbol, "\(state.battery.percent)", "%",
                       state.battery.percent <= 20 && !state.battery.isCharging
                       ? t.red : t.green)
            }
        case .disk:
            metric("internaldrive", String(format: "%.0f", state.stats.diskFreeGB), "G", t.teal)
        case .network:
            HStack(spacing: 6) {
                metric("arrow.down", SystemStats.rate(state.stats.netDown)
                    .replacingOccurrences(of: "/s", with: ""), "", t.blue)
            }
        case .clock:
            Text(DateKit.clock.string(from: state.now))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(t.primary)
                .monospacedDigit()
                .fixedSize()
        case .uptime:
            metric("power", DateKit.uptime(), "", t.secondary)
        case .shamsi:
            Text(shamsiShort)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(t.secondary)
                .fixedSize()
        case .date:
            Text(DateKit.gregShort.string(from: state.now))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(t.secondary)
                .fixedSize()
        case .presence:
            HStack(spacing: 6) {
                if p.watchClaude {
                    PresenceChip(source: .claude, running: state.presence.claude, theme: t)
                        .help("Claude: \(state.presence.claudeDetail)")
                }
                if p.watchChatGPT {
                    PresenceChip(source: .chatgpt, running: state.presence.chatgpt, theme: t)
                }
                if p.watchSpotify {
                    PresenceChip(source: .spotify, running: state.presence.spotify, theme: t)
                }
            }
        case .music:
            if state.music.isActive && state.music.isPlaying {
                HStack(spacing: 6) {
                    let musicTint = state.music.isAppleMusic
                        ? t.red : NotchSource.spotify.tint(t)
                    Artwork(image: state.music.artwork, tint: musicTint,
                            side: state.notchSize.height - 14, radius: 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(musicTint.opacity(0.35), lineWidth: 0.75))

                    Text(state.music.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(t.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 58, alignment: .leading)

                    if p.showVisualizer {
                        Visualizer(tint: state.music.isAppleMusic
                                   ? t.red : NotchSource.spotify.tint(t),
                                   active: true, bars: 3, maxHeight: 10)
                    }
                }
                .fixedSize()
            }
        case .timer:
            if timer.isRunning {
                HStack(spacing: 5) {
                    ZStack {
                        Circle().stroke(t.wellFill, lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: max(0.02, 1 - timer.fraction))
                            .stroke(timer.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 13, height: 13)
                    Text(timer.readout)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(t.primary)
                        .monospacedDigit()
                }
                .fixedSize()
            }
        }
    }

    private func metric(_ symbol: String, _ value: String, _ unit: String,
                        _ tint: Color) -> some View {
        HStack(spacing: 3.5) {
            ZStack {
                Circle().fill(tint.opacity(0.16))
                Image(systemName: symbol)
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 14, height: 14)

            HStack(alignment: .firstTextBaseline, spacing: 0.5) {
                Text(value)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(t.primary)
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(t.tertiary)
                }
            }
        }
        .fixedSize()
        .contentTransition(.numericText())
        .animation(.easeInOut(duration: 0.3), value: value)
    }

    private var shamsiShort: String {
        let s = DateKit.shamsiNumeric.string(from: state.now)
        return p.persianDigits ? DateKit.faDigits(s) : s
    }
}
