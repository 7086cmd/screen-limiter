import AppKit
import ScreenTime

/// `ScreenLimiter --probe <url>`: hands <url> to a fresh STWebpageController in each
/// window configuration and prints whether Screen Time reports it as blocked.
@MainActor
enum Probe {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--probe"), i + 1 < args.count,
              let url = URL(string: args[i + 1]) else { return false }
        let screen = NSScreen.main!.visibleFrame
        let o = CGPoint(x: screen.minX + 40, y: screen.minY + 40)
        struct Config { var name: String; var size: CGSize; var alpha: CGFloat = 1; var level: NSWindow.Level = .normal; var back = false }
        let all: [String: Config] = [
            "big": Config(name: "480x320 visible", size: CGSize(width: 480, height: 320)),
            "alpha0": Config(name: "480x320 alpha 0", size: CGSize(width: 480, height: 320), alpha: 0),
            "alpha02": Config(name: "480x320 alpha 0.02", size: CGSize(width: 480, height: 320), alpha: 0.02),
            "desktop": Config(name: "480x320 desktop level", size: CGSize(width: 480, height: 320), level: NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))),
            "back": Config(name: "480x320 ordered back", size: CGSize(width: 480, height: 320), back: true),
            "mid": Config(name: "200x120 visible", size: CGSize(width: 200, height: 120)),
            "small": Config(name: "80x50 visible", size: CGSize(width: 80, height: 50)),
            "tiny": Config(name: "20x20 visible", size: CGSize(width: 20, height: 20)),
        ]
        let order = (i + 2 < args.count ? args[i + 2] : "big").split(separator: ",").map(String.init)
        if order.first == "reuse" || order.first == "nowin" || order.first == "pixel" {
            let mode = order.first!
            let controller = STWebpageController()
            if mode != "nowin" {
                let size = mode == "pixel" ? CGSize(width: 1, height: 1) : CGSize(width: 20, height: 20)
                let w = NSWindow(contentRect: NSRect(origin: o, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                w.isReleasedWhenClosed = false
                w.alphaValue = 0
                controller.view.frame = NSRect(origin: .zero, size: size)
                w.contentView = controller.view
                w.orderFrontRegardless()
            }
            let other = URL(string: "https://github.com/")!
            let steps: [(String, URL?)] = [("youtube", url), ("nil", nil), ("github", other), ("youtube again", url),
                                           ("github", other), ("youtube 3rd", url), ("same url re-set", url)]
            for (label, u) in steps {
                if label == "same url re-set" { controller.url = nil }
                controller.url = u
                let start = Date()
                var at: Double?
                while Date().timeIntervalSince(start) < 3 {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                    if controller.urlIsBlocked, at == nil { at = Date().timeIntervalSince(start) }
                }
                print("[\(mode)] \(label): blocked=\(controller.urlIsBlocked)" + (at.map { String(format: " after %.1fs", $0) } ?? ""))
            }
            return true
        }
        let configs = order.compactMap { all[$0] }
        for config in configs {
            let controller = STWebpageController()
            let w = NSWindow(contentRect: NSRect(origin: o, size: config.size), styleMask: [.borderless], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.alphaValue = config.alpha
            w.level = config.level
            controller.view.frame = NSRect(origin: .zero, size: config.size)
            controller.view.autoresizingMask = [.width, .height]
            w.contentView = controller.view
            if config.back { w.orderBack(nil) } else { w.orderFrontRegardless() }
            controller.url = url
            var blockedAt: Double?
            let start = Date()
            while Date().timeIntervalSince(start) < 6 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                if controller.urlIsBlocked, blockedAt == nil { blockedAt = Date().timeIntervalSince(start) }
            }
            let occl = w.occlusionState.contains(.visible) ? "visible" : "occluded"
            print("[\(config.name)] blocked=\(controller.urlIsBlocked)"
                  + (blockedAt.map { String(format: " after %.1fs", $0) } ?? "") + " occlusion=\(occl)")
            controller.url = nil
            w.orderOut(nil)
        }
        return true
    }
}
