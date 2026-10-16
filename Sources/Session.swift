import AppKit
import UniformTypeIdentifiers

/// One capture: overlay windows on every display, torn down when the user finishes or cancels.
final class CaptureSession {
    enum Output { case copy, save, print, share }

    private var windows: [OverlayWindow] = []
    private var views: [OverlayView] = []
    var onEnd: (() -> Void)?

    init(captures: [(NSScreen, CGImage)]) {
        for (screen, cg) in captures {
            let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: false)
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.isReleasedWhenClosed = false
            w.hasShadow = false
            w.animationBehavior = .none
            w.acceptsMouseMovedEvents = true

            let image = NSImage(cgImage: cg, size: screen.frame.size)
            let background = NSImageView(frame: CGRect(origin: .zero, size: screen.frame.size))
            background.image = image
            background.imageScaling = .scaleAxesIndependently
            let overlay = OverlayView(frame: background.bounds, screenshot: image)
            overlay.autoresizingMask = [.width, .height]
            overlay.session = self
            background.addSubview(overlay)
            w.contentView = background

            windows.append(w)
            views.append(overlay)
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        windows.forEach { $0.orderFrontRegardless() }
        let mouse = NSEvent.mouseLocation
        let i = windows.firstIndex { $0.frame.contains(mouse) } ?? 0
        windows[i].makeKeyAndOrderFront(nil)
        windows[i].makeFirstResponder(views[i])
        NSCursor.crosshair.set()
    }

    func didBeginSelection(in view: OverlayView) {
        views.filter { $0 !== view }.forEach { $0.reset() }
    }

    func finish(_ output: Output, from view: OverlayView) {
        guard let rep = view.render() else { return }
        end()
        // Let the overlay disappear before any panel shows.
        DispatchQueue.main.async {
            switch output {
            case .copy: Exporter.copy(rep)
            case .save: Exporter.save(rep)
            case .print: Exporter.print(rep)
            case .share: Exporter.share(rep)
            }
        }
    }

    func cancel() { end() }

    private func end() {
        windows.forEach { $0.orderOut(nil) }
        let keepAlive = (windows, views)
        windows.removeAll()
        views.removeAll()
        DispatchQueue.main.async { _ = keepAlive; self.onEnd?() }
    }
}

enum Exporter {
    static func image(_ rep: NSBitmapImageRep) -> NSImage {
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }

    static func copy(_ rep: NSBitmapImageRep) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png = rep.representation(using: .png, properties: [:]) { pb.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
    }

    static func save(_ rep: NSBitmapImageRep) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        panel.nameFieldStringValue = "Screenshot \(f.string(from: Date())).png"
        let last = UserDefaults.standard.string(forKey: "lastSaveDir")
        panel.directoryURL = URL(fileURLWithPath: last ?? NSHomeDirectory() + "/Desktop")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let jpeg = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
        let data = rep.representation(using: jpeg ? .jpeg : .png,
                                      properties: jpeg ? [.compressionFactor: 0.9] : [:])
        do {
            try data?.write(to: url)
            UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: "lastSaveDir")
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    static func print(_ rep: NSBitmapImageRep) {
        NSApp.activate(ignoringOtherApps: true)
        let view = NSImageView(frame: CGRect(origin: .zero, size: rep.size))
        view.image = image(rep)
        view.imageScaling = .scaleProportionallyDown
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        NSPrintOperation(view: view, printInfo: info).run()
    }

    /// Per-user temp folder for files handed to the share sheet; emptied on launch and before each share.
    static let shareDir = FileManager.default.temporaryDirectory.appendingPathComponent("LightSnap-share")

    static func clearShareDir() { try? FileManager.default.removeItem(at: shareDir) }

    static func share(_ rep: NSBitmapImageRep) {
        // Share a real PNG file so every service (Mail, Messages, AirDrop…) can take it.
        clearShareDir()
        try? FileManager.default.createDirectory(at: shareDir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let url = shareDir.appendingPathComponent("Screenshot.png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url, options: .atomic)
        guard let button = AppDelegate.shared.statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        NSSharingServicePicker(items: [url]).show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
