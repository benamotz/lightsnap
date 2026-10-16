import AppKit

/// Small white floating bar of icon buttons, laid out manually (vertical or horizontal).
final class ToolbarView: NSView {
    private let vertical: Bool
    private(set) var buttons: [NSButton] = []
    private let size: CGFloat = 28, pad: CGFloat = 3, gap: CGFloat = 2

    init(vertical: Bool) {
        self.vertical = vertical
        super.init(frame: .zero)
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 5
        layer?.borderColor = NSColor(white: 0, alpha: 0.15).cgColor
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    @discardableResult
    func add(symbol: String, tip: String, tag: Int = 0, target: AnyObject, action: Selector) -> NSButton {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        return add(image: img ?? NSImage(), tip: tip, tag: tag, target: target, action: action)
    }

    @discardableResult
    func add(image: NSImage, tip: String, tag: Int = 0, target: AnyObject, action: Selector) -> NSButton {
        let b = NSButton(frame: NSRect(x: 0, y: 0, width: size, height: size))
        b.isBordered = false
        b.image = image
        b.imagePosition = .imageOnly
        b.imageScaling = .scaleNone
        b.contentTintColor = NSColor(white: 0.2, alpha: 1)
        b.toolTip = tip
        b.tag = tag
        b.target = target
        b.action = action
        b.refusesFirstResponder = true
        b.wantsLayer = true
        b.layer?.cornerRadius = 4
        buttons.append(b)
        addSubview(b)
        relayout()
        return b
    }

    private func relayout() {
        for (i, b) in buttons.enumerated() {
            let off = pad + CGFloat(i) * (size + gap)
            b.frame.origin = vertical ? CGPoint(x: pad, y: off) : CGPoint(x: off, y: pad)
        }
        let length = 2 * pad + CGFloat(buttons.count) * size + CGFloat(max(0, buttons.count - 1)) * gap
        let thickness = size + 2 * pad
        setFrameSize(vertical ? NSSize(width: thickness, height: length) : NSSize(width: length, height: thickness))
    }

    static func setActive(_ b: NSButton, _ active: Bool) {
        b.layer?.backgroundColor = active ? NSColor.systemBlue.withAlphaComponent(0.22).cgColor : nil
    }

    static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { r in
            let oval = NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1))
            color.setFill()
            oval.fill()
            NSColor(white: 0, alpha: 0.35).setStroke()
            oval.stroke()
            return true
        }
    }
}
