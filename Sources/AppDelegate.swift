import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!
    var statusItem: NSStatusItem!
    private var session: CaptureSession?
    private var capturing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        Exporter.clearShareDir()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "LightSnap")
        icon?.isTemplate = true
        statusItem.button?.image = icon

        let menu = NSMenu()
        let take = menu.addItem(withTitle: "Take Screenshot", action: #selector(captureFromMenu), keyEquivalent: "9")
        take.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit LightSnap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        menu.delegate = self
        statusItem.menu = menu

        if !HotKey.register({ [weak self] in self?.startCapture() }) {
            NSLog("LightSnap: ⌘⇧9 is already taken by another app")
        }
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    @objc private func captureFromMenu() {
        // Give the menu time to fade so it isn't in the shot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.startCapture() }
    }

    func startCapture() {
        guard session == nil, !capturing else { return }
        capturing = true
        Task { @MainActor in
            defer { capturing = false }
            do {
                let captures = try await ScreenCapturer.captureAll()
                guard !captures.isEmpty else { return }
                let s = CaptureSession(captures: captures)
                s.onEnd = { [weak self] in self?.session = nil }
                session = s
                s.show()
            } catch {
                showPermissionAlert(error)
            }
        }
    }

    private func showPermissionAlert(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "LightSnap can't capture the screen"
        alert.informativeText = "Allow LightSnap under System Settings › Privacy & Security › Screen & System Audio Recording, then try again.\n\n(\(error.localizedDescription))"
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLogin(_ item: NSMenuItem) {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menu.item(withTitle: "Launch at Login")?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
