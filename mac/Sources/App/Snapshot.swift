import AppKit
import SwiftUI

/// `ScreenLimiter --snapshot <dir>` renders the UI to PNGs (for design review), then quits.
@MainActor
enum Snapshot {
    static func runIfRequested(bridge: Bridge) -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let scenarios: [(String, Bridge.Status)] = [
            ("menu-reporting", .reporting(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!)),
            ("menu-paused", .paused("Google Chrome isn't the frontmost app")),
            ("menu-blocked", .blocked("youtube.com")),
            ("menu-not-connected", .notConnected),
        ]
        for (name, status) in scenarios {
            bridge.loadDemoState(status)
            render(MenuView().environment(bridge), size: nil, to: dir.appending(path: "\(name).png"))
        }
        bridge.loadDemoState(.reporting(URL(string: "https://www.youtube.com/")!))
        render(SettingsView().environment(bridge), size: CGSize(width: 560, height: 500), to: dir.appending(path: "settings.png"))
        return true
    }

    private static func render(_ view: some View, size: CGSize?, to url: URL) {
        let host = NSHostingView(rootView: view.background(.windowBackground))
        let fitting = size ?? host.fittingSize
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: fitting.width, height: fitting.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
