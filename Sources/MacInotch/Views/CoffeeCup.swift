import SwiftUI

struct CupBody: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.16
        let top = rect.minY + rect.height * 0.06
        let bottom = rect.maxY - rect.height * 0.04
        let taper = rect.width * 0.09

        path.move(to: CGPoint(x: rect.minX + inset, y: top))
        path.addLine(to: CGPoint(x: rect.minX + inset + taper, y: bottom - taper))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - inset - taper, y: bottom - taper),
            control: CGPoint(x: rect.midX, y: bottom + taper * 0.9))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: top))
        path.closeSubpath()
        return path
    }
}

struct CupHandle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.maxX - rect.width * 0.17
        let y = rect.minY + rect.height * 0.30
        path.move(to: CGPoint(x: x, y: y))
        path.addCurve(
            to: CGPoint(x: x, y: y + rect.height * 0.30),
            control1: CGPoint(x: x + rect.width * 0.26, y: y - rect.height * 0.04),
            control2: CGPoint(x: x + rect.width * 0.26, y: y + rect.height * 0.34))
        return path
    }
}

struct SteamWisp: Shape {
    var phase: Double
    var amplitude: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 12
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let y = rect.maxY - t * rect.height
            let wobble = sin(t * .pi * 2.1 + phase) * amplitude * (0.25 + t)
            let x = rect.midX + wobble
            if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

struct CoffeeCup: View {
    var fill: Double
    var active: Bool
    var tint: Color
    var shell: Color

    private let brew = Color(red: 0.36, green: 0.20, blue: 0.11)

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cup = CGRect(x: 0, y: side * 0.30, width: side, height: side * 0.70)

            ZStack(alignment: .topLeading) {
                if active {
                    TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        ZStack {
                            wisp(time: time, offset: 0, x: -side * 0.14, side: side)
                            wisp(time: time, offset: 1.7, x: 0, side: side)
                            wisp(time: time, offset: 3.1, x: side * 0.14, side: side)
                        }
                        .frame(width: side, height: side * 0.30)
                    }
                }

                ZStack {
                    CupHandle()
                        .stroke(shell, style: StrokeStyle(lineWidth: side * 0.075,
                                                          lineCap: .round))
                        .frame(width: cup.width, height: cup.height)

                    CupBody()
                        .fill(shell.opacity(0.16))
                        .frame(width: cup.width, height: cup.height)

                    CupBody()
                        .fill(
                            LinearGradient(colors: [brew.opacity(0.95), tint],
                                           startPoint: .bottom, endPoint: .top)
                        )
                        .frame(width: cup.width, height: cup.height)
                        .mask(alignment: .bottom) {
                            Rectangle()
                                .frame(height: cup.height * max(0, min(1, fill)))
                        }

                    CupBody()
                        .stroke(shell, lineWidth: side * 0.07)
                        .frame(width: cup.width, height: cup.height)
                }
                .offset(y: cup.minY)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func wisp(time: Double, offset: Double, x: CGFloat, side: CGFloat) -> some View {
        let phase = time * 1.6 + offset
        let rise = (time * 0.55 + offset / 6).truncatingRemainder(dividingBy: 1)
        return SteamWisp(phase: phase, amplitude: side * 0.075)
            .stroke(shell.opacity((1 - rise) * 0.55), style: StrokeStyle(
                lineWidth: side * 0.055, lineCap: .round))
            .frame(width: side * 0.30, height: side * 0.26)
            .offset(x: x, y: -rise * side * 0.10)
    }
}
