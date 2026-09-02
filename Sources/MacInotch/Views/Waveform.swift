import SwiftUI

struct Waveform: View {
    var levels: [Double]
    var tint: Color
    var barWidth: CGFloat = 2.4
    var spacing: CGFloat = 2.2

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    let edge = edgeFade(index)
                    let value = max(0.06, level * edge)
                    Capsule()
                        .fill(tint.opacity(0.35 + 0.65 * value))
                        .frame(width: barWidth, height: max(2, height * value))
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .center)
            .animation(.easeOut(duration: 0.09), value: levels)
        }
    }

    private func edgeFade(_ index: Int) -> Double {
        guard levels.count > 4 else { return 1 }
        let position = Double(index) / Double(levels.count - 1)
        let distance = abs(position - 0.5) * 2
        return 0.55 + 0.45 * (1 - distance * distance)
    }
}
