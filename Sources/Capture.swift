import AppKit
import ScreenCaptureKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

enum ScreenCapturer {
    /// Freezes every display at full backing resolution.
    @MainActor
    static func captureAll() async throws -> [(NSScreen, CGImage)] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var result: [(NSScreen, CGImage)] = []
        for screen in NSScreen.screens {
            guard let id = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            result.append((screen, image))
        }
        return result
    }
}
