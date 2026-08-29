import AppKit

enum MenuBarIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 19, height: 13)
        let image = NSImage(size: size, flipped: false) { _ in
            let panel = NSRect(x: 0.5, y: 1, width: size.width - 1, height: size.height - 2)
            let body = NSBezierPath(roundedRect: panel, xRadius: 3.2, yRadius: 3.2)

            let nw = panel.width * 0.46
            let nh: CGFloat = 4.0
            let x = panel.midX - nw / 2
            let top = panel.maxY
            let notch = NSBezierPath()
            notch.move(to: CGPoint(x: x, y: top + 1))
            notch.line(to: CGPoint(x: x, y: top - nh + 1.4))
            notch.curve(to: CGPoint(x: x + 1.4, y: top - nh),
                        controlPoint1: CGPoint(x: x, y: top - nh),
                        controlPoint2: CGPoint(x: x, y: top - nh))
            notch.line(to: CGPoint(x: x + nw - 1.4, y: top - nh))
            notch.curve(to: CGPoint(x: x + nw, y: top - nh + 1.4),
                        controlPoint1: CGPoint(x: x + nw, y: top - nh),
                        controlPoint2: CGPoint(x: x + nw, y: top - nh))
            notch.line(to: CGPoint(x: x + nw, y: top + 1))
            notch.close()

            let combined = NSBezierPath()
            combined.append(body)
            combined.append(notch)
            combined.windingRule = .evenOdd
            NSColor.black.setFill()
            combined.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
