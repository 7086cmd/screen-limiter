import AppKit
import SwiftUI

@main
struct ScreenLimiterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var bridge = Bridge.shared

    init() {
        let bridge = _bridge.wrappedValue
        if Probe.runIfRequested() { exit(0) }
        if Snapshot.runIfRequested(bridge: bridge) { exit(0) }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(bridge)
        } label: {
            Image(systemName: bridge.menuBarSymbol)
                .accessibilityLabel("Screen Limiter")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(bridge)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Zero-setup: register the native-messaging host for every installed browser.
        for browser in Browser.allCases where browser.isInstalled && !NativeHostInstaller.isInstalled(for: browser) {
            _ = try? NativeHostInstaller.install(for: browser)
        }
    }
}

enum SystemLinks {
    static let screenTimeSettings = URL(string: "x-apple.systempreferences:com.apple.Screen-Time-Settings.extension")!

    static func openScreenTimeSettings() {
        NSWorkspace.shared.open(screenTimeSettings)
    }
}

extension Browser {
    var appURL: URL? {
        bundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    var isInstalled: Bool { appURL != nil }

    var icon: NSImage {
        if let appURL { return NSWorkspace.shared.icon(forFile: appURL.path) }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
    }
}

extension Bridge {
    var menuBarSymbol: String {
        switch status {
        case .blocked: "hourglass.bottomhalf.filled"
        case .reporting: "hourglass"
        case .paused, .notConnected: "hourglass.tophalf.filled"
        }
    }
}
