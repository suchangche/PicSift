import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var openMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ application: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let window = application.windows.first(where: {
                !($0 is NSPanel)
                    && $0.styleMask.contains(.titled)
                    && $0.level == .normal
                    && $0.contentView != nil
            }) {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
            } else {
                openMainWindow?()
            }
        }
        application.activate(ignoringOtherApps: true)
        return true
    }
}
