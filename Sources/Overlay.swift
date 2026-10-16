import AppKit

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// One per display: frozen screenshot underneath, dimming + selection + annotations drawn here.
final class OverlayView: NSView, NSTextFieldDelegate {
    weak var session: CaptureSession?
    let screenshot: NSImage

    private(set) var selection: CGRect?
    private var annotations: [Annotation] = []
    private var current: Annotation?
    private var tool: Tool = .none
    private var color: NSColor = .systemRed
    private var textField: NSTextField?

    private enum Drag {
        case none, selecting(CGPoint), moving(CGPoint, CGRect), resizing(Int, CGRect), drawing
    }
    private var drag: Drag = .none

    private let toolBar = ToolbarView(vertical: true)
    private let actionBar = ToolbarView(vertical: false)
    private let palette = ToolbarView(vertical: false)
    private var toolButtons: [Tool: NSButton] = [:]
    private var colorButton: NSButton!

    private static let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen,
                                            .systemBlue, .systemPurple, .black, .white]
    // Handle directions: -1 = min edge, 1 = max edge, 0 = middle.
    private static let handleDirs: [(CGFloat, CGFloat)] = [(-1, -1), (0, -1), (1, -1), (1, 0),
                                                           (1, 1), (0, 1), (-1, 1), (-1, 0)]

    init(frame: NSRect, screenshot: NSImage) {
        self.screenshot = screenshot
        super.init(frame: frame)
        buildToolbars()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Toolbars

    private func buildToolbars() {
        let tools: [(Tool, String, String)] = [
            (.pen, "pencil.tip", "Pen"), (.line, "line.diagonal", "Line"),
            (.arrow, "arrow.up.right", "Arrow"), (.rect, "rectangle", "Rectangle"),
            (.ellipse, "circle", "Ellipse"), (.marker, "highlighter", "Marker"),
            (.text, "textformat", "Text"),
        ]
        for (t, symbol, tip) in tools {
            toolButtons[t] = toolBar.add(symbol: symbol, tip: tip, tag: t.rawValue,
                                         target: self, action: #selector(toolClicked(_:)))
        }
        colorButton = toolBar.add(image: ToolbarView.swatch(color), tip: "Color",
                                  target: self, action: #selector(colorClicked))
        toolBar.add(symbol: "arrow.uturn.backward", tip: "Undo (⌘Z)", target: self, action: #selector(undo))

        actionBar.add(symbol: "printer", tip: "Print (⌘P)", target: self, action: #selector(printClicked))
        actionBar.add(symbol: "square.and.arrow.up", tip: "Share", target: self, action: #selector(shareClicked))
        actionBar.add(symbol: "doc.on.doc", tip: "Copy (⌘C)", target: self, action: #selector(copyClicked))
        actionBar.add(symbol: "square.and.arrow.down", tip: "Save (⌘S)", target: self, action: #selector(saveClicked))
        actionBar.add(symbol: "xmark", tip: "Close (Esc)", target: self, action: #selector(closeClicked))

        for (i, c) in Self.colors.enumerated() {
            palette.add(image: ToolbarView.swatch(c), tip: "", tag: i, target: self, action: #selector(paletteClicked(_:)))
        }
        for bar in [toolBar, actionBar, palette] {
            bar.isHidden = true
            addSubview(bar)
        }
    }

    private func layoutToolbars() {
        palette.isHidden = true
        guard let s = selection, case .none = drag else {
            toolBar.isHidden = true
            actionBar.isHidden = true
            return
        }
        toolBar.isHidden = false
        actionBar.isHidden = false
        let m: CGFloat = 6
        let tb = toolBar.frame.size
        var x = s.maxX + m
        if x + tb.width > bounds.maxX - 4 { x = s.minX - m - tb.width }
        if x < 4 { x = s.maxX - tb.width - m }
        let y = min(max(s.minY, 4), bounds.maxY - tb.height - 4)
        toolBar.setFrameOrigin(CGPoint(x: x, y: y))

        let ab = actionBar.frame.size
        let ax = min(max(s.maxX - ab.width, 4), bounds.maxX - ab.width - 4)
        var ay = s.minY - m - ab.height
        if ay < 4 { ay = s.minY + m }
        actionBar.setFrameOrigin(CGPoint(x: ax, y: ay))
    }

    @objc private func toolClicked(_ sender: NSButton) {
        commitText()
        let t = Tool(rawValue: sender.tag) ?? .none
        tool = (tool == t) ? .none : t
        for (k, b) in toolButtons { ToolbarView.setActive(b, k == tool) }
        palette.isHidden = true
    }

    @objc private func colorClicked() {
        if !palette.isHidden { palette.isHidden = true; return }
        let btn = convert(colorButton.frame, from: toolBar)
        let w = palette.frame.width
        var x = toolBar.frame.minX - w - 4
        if x < 4 { x = toolBar.frame.maxX + 4 }
        palette.setFrameOrigin(CGPoint(x: x, y: btn.midY - palette.frame.height / 2))
        palette.isHidden = false
    }

    @objc private func paletteClicked(_ sender: NSButton) {
        color = Self.colors[sender.tag]
        colorButton.image = ToolbarView.swatch(color)
        textField?.textColor = color
        palette.isHidden = true
    }

    @objc private func undo() {
        guard textField == nil else { return }
        _ = annotations.popLast()
        needsDisplay = true
    }

    @objc private func copyClicked() { commitText(); session?.finish(.copy, from: self) }
    @objc private func saveClicked() { commitText(); session?.finish(.save, from: self) }
    @objc private func printClicked() { commitText(); session?.finish(.print, from: self) }
    @objc private func shareClicked() { commitText(); session?.finish(.share, from: self) }
    @objc private func closeClicked() { session?.cancel() }

    // MARK: - Public

    func reset() {
        commitText()
        selection = nil
        annotations.removeAll()
        drag = .none
        layoutToolbars()
        needsDisplay = true
    }

    /// Renders the selected region (screenshot + annotations) at native pixel resolution.
    func render() -> NSBitmapImageRep? {
        guard let s = selection, s.width >= 1, s.height >= 1 else { return nil }
        let scale = window?.backingScaleFactor ?? 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int((s.width * scale).rounded()),
                                         pixelsHigh: Int((s.height * scale).rounded()),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = s.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        let t = NSAffineTransform()
        t.translateX(by: -s.minX, yBy: -s.minY)
        t.concat()
        screenshot.draw(in: bounds)
        annotations.forEach { $0.draw() }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        if let s = selection {
            dim.appendRect(s)
            dim.windingRule = .evenOdd
        }
        NSColor(white: 0, alpha: 0.45).setFill()
        dim.fill()
        guard let s = selection else { return }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: s).addClip()
        annotations.forEach { $0.draw() }
        current?.draw()
        NSGraphicsContext.restoreGraphicsState()

        let border = NSBezierPath(rect: s.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        NSColor(white: 0, alpha: 0.6).setStroke()
        border.stroke()
        border.setLineDash([4, 4], count: 2, phase: 0)
        NSColor.white.setStroke()
        border.stroke()

        if case .drawing = drag {} else {
            for i in 0..<8 {
                let p = handlePoint(i, s)
                let r = NSBezierPath(rect: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
                NSColor.white.setFill()
                r.fill()
                NSColor(white: 0.25, alpha: 1).setStroke()
                r.lineWidth = 1
                r.stroke()
            }
        }
        drawSizeLabel(s)
    }

    private func drawSizeLabel(_ s: CGRect) {
        let scale = window?.backingScaleFactor ?? 1
        let str = "\(Int(s.width * scale)) × \(Int(s.height * scale))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let sz = str.size(withAttributes: attrs)
        var o = CGPoint(x: s.minX, y: s.maxY + 4)
        if o.y + sz.height + 4 > bounds.maxY { o.y = s.maxY - sz.height - 8; o.x += 4 }
        let bg = CGRect(x: o.x, y: o.y, width: sz.width + 8, height: sz.height + 4)
        NSColor(white: 0, alpha: 0.7).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 3, yRadius: 3).fill()
        str.draw(at: CGPoint(x: o.x + 4, y: o.y + 2), withAttributes: attrs)
    }

    // MARK: - Geometry

    private func handlePoint(_ i: Int, _ s: CGRect) -> CGPoint {
        let (dx, dy) = Self.handleDirs[i]
        return CGPoint(x: dx < 0 ? s.minX : dx > 0 ? s.maxX : s.midX,
                       y: dy < 0 ? s.minY : dy > 0 ? s.maxY : s.midY)
    }

    private func handleIndex(at p: CGPoint) -> Int? {
        guard let s = selection else { return nil }
        return (0..<8).first { i in
            let h = handlePoint(i, s)
            return abs(h.x - p.x) <= 6 && abs(h.y - p.y) <= 6
        }
    }

    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(p.x.rounded(), 0), bounds.maxX), y: min(max(p.y.rounded(), 0), bounds.maxY))
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let p = point(event)
        commitText()
        palette.isHidden = true

        if let s = selection {
            if let h = handleIndex(at: p) {
                drag = .resizing(h, s)
                layoutToolbars()
                return
            }
            if s.contains(p) {
                switch tool {
                case .text:
                    beginText(at: p)
                case .none:
                    drag = .moving(p, s)
                    layoutToolbars()
                default:
                    current = Annotation(tool: tool, color: color, points: [p])
                    drag = .drawing
                }
                return
            }
        }
        session?.didBeginSelection(in: self)
        annotations.removeAll()
        selection = nil
        drag = .selecting(p)
        layoutToolbars()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = point(event)
        switch drag {
        case .selecting(let start):
            selection = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                               width: abs(p.x - start.x), height: abs(p.y - start.y))
        case .moving(let start, let orig):
            var r = orig.offsetBy(dx: p.x - start.x, dy: p.y - start.y)
            r.origin.x = min(max(r.origin.x, 0), bounds.width - r.width)
            r.origin.y = min(max(r.origin.y, 0), bounds.height - r.height)
            selection = r
        case .resizing(let h, let orig):
            let (dx, dy) = Self.handleDirs[h]
            var x0 = orig.minX, x1 = orig.maxX, y0 = orig.minY, y1 = orig.maxY
            if dx < 0 { x0 = p.x } else if dx > 0 { x1 = p.x }
            if dy < 0 { y0 = p.y } else if dy > 0 { y1 = p.y }
            selection = CGRect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0))
        case .drawing:
            guard var c = current else { break }
            switch c.tool {
            case .pen, .marker: c.points.append(p)
            default: c.points = [c.points[0], p]
            }
            current = c
        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch drag {
        case .selecting:
            if let s = selection, s.width < 4 || s.height < 4 { selection = nil }
        case .drawing:
            if let c = current, c.isValid { annotations.append(c) }
            current = nil
        default:
            break
        }
        drag = .none
        layoutToolbars()
        needsDisplay = true
        updateCursor(point(event))
    }

    override func rightMouseDown(with event: NSEvent) { session?.cancel() }

    override func mouseMoved(with event: NSEvent) { updateCursor(convert(event.locationInWindow, from: nil)) }

    private func updateCursor(_ p: CGPoint) {
        if let hit = hitTest(convert(p, to: superview)), hit !== self {
            NSCursor.arrow.set()
            return
        }
        guard let s = selection else { NSCursor.crosshair.set(); return }
        if let h = handleIndex(at: p) {
            switch h {
            case 1, 5: NSCursor.resizeUpDown.set()
            case 3, 7: NSCursor.resizeLeftRight.set()
            default: NSCursor.crosshair.set()
            }
        } else if s.contains(p) {
            switch tool {
            case .none: NSCursor.openHand.set()
            case .text: NSCursor.iBeam.set()
            default: NSCursor.crosshair.set()
            }
        } else {
            NSCursor.crosshair.set()
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command)
        switch (Int(event.keyCode), cmd) {
        case (53, _): session?.cancel()                    // Esc
        case (36, _), (76, _): copyClicked()               // Return / Enter
        case (8, true): copyClicked()                      // ⌘C
        case (1, true): saveClicked()                      // ⌘S
        case (35, true): printClicked()                    // ⌘P
        case (6, true): undo()                             // ⌘Z
        case (0, true):                                    // ⌘A — whole screen
            session?.didBeginSelection(in: self)
            selection = bounds
            layoutToolbars()
            needsDisplay = true
        default: super.keyDown(with: event)
        }
    }

    // MARK: - Text tool

    private func beginText(at p: CGPoint) {
        let f = NSTextField(string: "")
        f.font = Annotation.textFont
        f.textColor = color
        f.isBordered = false
        f.isBezeled = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.delegate = self
        f.wantsLayer = true
        f.layer?.borderColor = NSColor(white: 1, alpha: 0.8).cgColor
        f.layer?.borderWidth = 1
        f.frame = CGRect(x: p.x - 2, y: p.y - 12, width: 60, height: 24)
        addSubview(f)
        window?.makeFirstResponder(f)
        textField = f
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let f = textField else { return }
        let w = (f.stringValue as NSString).size(withAttributes: [.font: Annotation.textFont]).width
        f.frame.size.width = max(60, w + 16)
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            textField?.stringValue = ""
            commitText()
            return true
        }
        if sel == #selector(NSResponder.insertNewline(_:)) {
            commitText()
            return true
        }
        return false
    }

    private func commitText() {
        guard let f = textField else { return }
        textField = nil
        let a = Annotation(tool: .text, color: f.textColor ?? color,
                           points: [CGPoint(x: f.frame.minX + 2, y: f.frame.minY + 1)], text: f.stringValue)
        f.removeFromSuperview()
        window?.makeFirstResponder(self)
        if a.isValid { annotations.append(a) }
        needsDisplay = true
    }
}
