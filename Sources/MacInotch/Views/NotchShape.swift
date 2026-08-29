import SwiftUI

struct NotchShape: Shape {
    var bottomRadius: CGFloat = 14
    var topRadius: CGFloat = 8
    var bandWidth: CGFloat = 0
    var bandHeight: CGFloat = 0
    var flareRadius: CGFloat = 9

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>,
                                       AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(bottomRadius, topRadius), .init(bandWidth, bandHeight)) }
        set {
            bottomRadius = newValue.first.first
            topRadius = newValue.first.second
            bandWidth = newValue.second.first
            bandHeight = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        if bandWidth > 0, bandWidth < rect.width - 1, bandHeight > 0 {
            return chinPath(in: rect)
        }
        return plainPath(in: rect)
    }

    private func plainPath(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let br = min(bottomRadius, min(w, h) / 2)
        let tr = min(topRadius, min(w, h) / 2)

        p.move(to: CGPoint(x: rect.minX - tr, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + tr),
                       control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.minX + br, y: rect.maxY),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - br),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + tr))
        p.addQuadCurve(to: CGPoint(x: rect.maxX + tr, y: rect.minY),
                       control: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }

    private func chinPath(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX
        let bl = cx - bandWidth / 2
        let br = cx + bandWidth / 2
        let bh = min(bandHeight, rect.height)
        let tr = min(topRadius, bandWidth / 2)
        let fr = min(flareRadius, min(bandWidth, rect.width - bandWidth) / 2)
        let cr = min(bottomRadius, rect.height / 2)
        let ct = min(bottomRadius * 0.7, (rect.height - bh) / 2)

        p.move(to: CGPoint(x: bl - tr, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: bl, y: rect.minY + tr),
                       control: CGPoint(x: bl, y: rect.minY))

        p.addLine(to: CGPoint(x: bl, y: bh - fr))
        p.addQuadCurve(to: CGPoint(x: bl - fr, y: bh),
                       control: CGPoint(x: bl, y: bh))

        p.addLine(to: CGPoint(x: rect.minX + ct, y: bh))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: bh + ct),
                       control: CGPoint(x: rect.minX, y: bh))

        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cr))
        p.addQuadCurve(to: CGPoint(x: rect.minX + cr, y: rect.maxY),
                       control: CGPoint(x: rect.minX, y: rect.maxY))

        p.addLine(to: CGPoint(x: rect.maxX - cr, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - cr),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))

        p.addLine(to: CGPoint(x: rect.maxX, y: bh + ct))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - ct, y: bh),
                       control: CGPoint(x: rect.maxX, y: bh))

        p.addLine(to: CGPoint(x: br + fr, y: bh))
        p.addQuadCurve(to: CGPoint(x: br, y: bh - fr),
                       control: CGPoint(x: br, y: bh))

        p.addLine(to: CGPoint(x: br, y: rect.minY + tr))
        p.addQuadCurve(to: CGPoint(x: br + tr, y: rect.minY),
                       control: CGPoint(x: br, y: rect.minY))

        p.closeSubpath()
        return p
    }
}
