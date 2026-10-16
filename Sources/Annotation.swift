import AppKit

enum Tool: Int {
    case none, pen, line, arrow, rect, ellipse, marker, text
}

struct Annotation {
    var tool: Tool
    var color: NSColor
    var points: [CGPoint]
    var text = ""

    static let textFont = NSFont.boldSystemFont(ofSize: 18)

    var isValid: Bool {
        switch tool {
        case .line, .arrow, .rect, .ellipse: return points.count >= 2 && points.first != points.last
        case .text: return !text.trimmingCharacters(in: .whitespaces).isEmpty
        case .none: return false
        default: return !points.isEmpty
        }
    }

    func draw() {
        guard let first = points.first, let last = points.last else { return }
        let box = CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                         width: abs(last.x - first.x), height: abs(last.y - first.y))
        let path = NSBezierPath()
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        color.setFill()

        switch tool {
        case .pen, .marker:
            path.move(to: first)
            if points.count == 1 { path.line(to: first) }
            for p in points.dropFirst() { path.line(to: p) }
            if tool == .marker {
                path.lineWidth = 16
                path.lineCapStyle = .square
                color.withAlphaComponent(0.4).setStroke()
            }
            path.stroke()
        case .line:
            path.move(to: first)
            path.line(to: last)
            path.stroke()
        case .arrow:
            let angle = atan2(last.y - first.y, last.x - first.x)
            let head: CGFloat = 16
            let base = CGPoint(x: last.x - cos(angle) * head * 0.8, y: last.y - sin(angle) * head * 0.8)
            path.move(to: first)
            path.line(to: base)
            path.stroke()
            let tip = NSBezierPath()
            tip.move(to: last)
            tip.line(to: CGPoint(x: last.x - head * cos(angle - .pi / 7), y: last.y - head * sin(angle - .pi / 7)))
            tip.line(to: CGPoint(x: last.x - head * cos(angle + .pi / 7), y: last.y - head * sin(angle + .pi / 7)))
            tip.close()
            tip.fill()
        case .rect:
            path.lineJoinStyle = .miter
            path.appendRect(box)
            path.stroke()
        case .ellipse:
            path.appendOval(in: box)
            path.stroke()
        case .text:
            (text as NSString).draw(at: first, withAttributes: [.font: Self.textFont, .foregroundColor: color])
        case .none:
            break
        }
    }
}
