import AppKit
import Observation
import OSLog
import ScreenTime

/// Feeds the browser's active tab into Screen Time through an `STWebpageController`
/// owned by this app, and tells the extension to block the tab when Screen Time
/// says the site is over its limit.
@MainActor
@Observable
final class Bridge {
    /// SwiftUI may build the App struct more than once; keep exactly one bridge.
    static let shared = Bridge()

    enum Status: Equatable {
        case notConnected
        case paused(String)
        case reporting(URL)
        case blocked(String)
    }

    // MARK: Observable state

    private(set) var status: Status = .notConnected
    private(set) var connectedBrowser: Browser?
    private(set) var tab: TabReport?
    private(set) var reportingURL: URL?
    private(set) var lastBlock: (domain: String, date: Date)?
    private(set) var ledger = ReportedLedger.load()
    private(set) var log: [LogEntry] = []

    var windowMode: BridgeWindowMode {
        didSet {
            UserDefaults.standard.set(windowMode.rawValue, forKey: "windowMode")
            placeWindow()
            record(.info, "Bridge window: \(windowMode.label)")
        }
    }

    /// Screen Time evaluates limits when the URL is set, so a limit that runs out while
    /// you stay on one page is only noticed when we hand the URL over again.
    var resubmitURL: Bool {
        didSet { UserDefaults.standard.set(resubmitURL, forKey: "resubmitURL") }
    }

    // MARK: Private

    /// Exactly one controller for the app's lifetime. Spike S7 found that only the first
    /// STWebpageController in a process ever gets a verdict from Screen Time, and only
    /// while its view is in a window (any window, even 1×1 and fully transparent).
    @ObservationIgnored private let webpage = STWebpageController()
    @ObservationIgnored private var window: NSPanel?
    @ObservationIgnored private var blockedObservation: NSKeyValueObservation?
    @ObservationIgnored private var lastMessageAt: Date?
    @ObservationIgnored private var frontmostBundleID: String?
    /// The URL we last sent a "blocked" message for, so each navigation is blocked once.
    @ObservationIgnored private var lastBlockedURL: URL?
    /// `urlIsBlocked` still holds the previous page's verdict for a moment after the URL
    /// changes (Screen Time answers in ~0.2–0.4 s), so ignore it until then.
    @ObservationIgnored private var verdictSettlesAt = Date.distantPast
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var demoMode = false
    @ObservationIgnored private let logger = Logger(subsystem: "dev.screenlimiter.mac", category: "bridge")

    private static let fromExtension = Notification.Name("dev.screenlimiter.fromExtension")
    private static let toExtension = Notification.Name("dev.screenlimiter.toExtension")
    private static let idleThreshold: TimeInterval = 60
    private static let staleAfter: TimeInterval = 75
    private static let resubmitEvery = 10

    private init() {
        let defaults = UserDefaults.standard
        windowMode = BridgeWindowMode(rawValue: defaults.string(forKey: "windowMode") ?? "") ?? .pixel
        resubmitURL = defaults.object(forKey: "resubmitURL") as? Bool ?? true
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        DistributedNotificationCenter.default().addObserver(
            forName: Self.fromExtension, object: nil, queue: .main
        ) { [weak self] note in
            guard let json = note.object as? String else { return }
            MainActor.assumeIsolated { self?.handle(json) }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.frontmostBundleID = app?.bundleIdentifier
                self?.apply()
            }
        }

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }

        blockedObservation = webpage.observe(\.urlIsBlocked, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.apply() }
        }
        placeWindow()
        record(.info, "Bridge started")
        send(["type": "hello"])
    }

    // MARK: Extension messages

    private func handle(_ json: String) {
        guard let data = json.data(using: .utf8),
              let report = try? JSONDecoder().decode(TabReport.self, from: data)
        else {
            record(.error, "Unreadable message: \(json.prefix(120))")
            return
        }

        switch report.type {
        case "hostConnected":
            lastMessageAt = Date()
            record(.info, "Native host connected")
        case "hostDisconnected":
            lastMessageAt = nil
            connectedBrowser = nil
            tab = nil
            record(.info, "Native host disconnected")
            apply()
        case "tab":
            lastMessageAt = Date()
            let browser = report.browser.flatMap(Browser.init(rawValue:))
            connectedBrowser = browser
            if tab?.url != report.url, let url = report.url {
                record(.report, "\(browser?.displayName ?? "Browser"): \(url)")
            }
            tab = report
            apply()
        default:
            break
        }
    }

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8) else { return }
        DistributedNotificationCenter.default().postNotificationName(
            Self.toExtension, object: json, userInfo: nil, deliverImmediately: true)
    }

    // MARK: Core logic

    private var extensionConnected: Bool {
        guard let lastMessageAt else { return false }
        return Date().timeIntervalSince(lastMessageAt) < Self.staleAfter
    }

    private var systemIdleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Decide which URL (if any) Screen Time should be recording right now.
    private func desiredURL() -> (URL?, reason: String?) {
        guard extensionConnected, let browser = connectedBrowser else {
            return (nil, "Browser extension isn't connected")
        }
        // `defaults write dev.screenlimiter.mac debugIgnoreFrontmost -bool YES` for scripted tests.
        let ignoreFront = UserDefaults.standard.bool(forKey: "debugIgnoreFrontmost")
        guard ignoreFront || Browser.from(bundleID: frontmostBundleID) == browser else {
            return (nil, "\(browser.displayName) isn't the frontmost app")
        }
        guard let tab, tab.windowFocused == true else {
            return (nil, "No focused \(browser.displayName) window")
        }
        if tab.idle == "idle" || tab.idle == "locked" || systemIdleSeconds > Self.idleThreshold {
            return (nil, "You're idle")
        }
        guard let url = tab.webURL else {
            return (nil, "Not a web page")
        }
        return (url, nil)
    }

    /// `urlIsBlocked` keeps its last value after the URL is cleared, so only trust it
    /// while a URL is set.
    private var isBlocked: Bool {
        webpage.url != nil && Date() >= verdictSettlesAt && webpage.urlIsBlocked
    }

    private func apply() {
        guard !demoMode else { return }
        let (url, reason) = desiredURL()

        if webpage.url != url {
            // Header guidance: clear the video flag before changing URL.
            webpage.urlIsPlayingVideo = false
            webpage.url = url
            verdictSettlesAt = Date().addingTimeInterval(1)
            if url == nil { lastBlockedURL = nil }
            if url != nil {
                // Re-check once the verdict has settled rather than waiting for the next tick.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) { [weak self] in self?.apply() }
            }
            record(.info, url.map { "Screen Time ← \($0.absoluteString)" } ?? "Screen Time ← nothing (\(reason ?? "paused"))")
        }
        webpage.urlIsPlayingVideo = url != nil && tab?.audible == true
        reportingURL = url
        checkBlocked()

        if isBlocked, let url {
            status = .blocked(url.displayDomain)
        } else if let url {
            status = .reporting(url)
        } else if !extensionConnected {
            status = .notConnected
        } else {
            status = .paused(reason ?? "Paused")
        }
    }

    private func checkBlocked() {
        guard isBlocked, let url = reportingURL else {
            lastBlockedURL = nil
            return
        }
        guard url != lastBlockedURL else { return }
        lastBlockedURL = url

        let domain = url.displayDomain
        lastBlock = (domain, Date())
        record(.blocked, "Screen Time blocked \(domain) — asking the extension to close it")
        send(["type": "blocked", "url": url.absoluteString, "domain": domain])
    }

    private func tick() {
        ticks += 1
        if let url = reportingURL, !isBlocked {
            ledger.add(1, to: url.displayDomain)
            if ticks % 10 == 0 { ledger.save() }
        }
        if resubmitURL, ticks % Self.resubmitEvery == 0, let url = webpage.url, !isBlocked {
            webpage.url = nil
            webpage.url = url
        }
        // Re-evaluate idle/staleness, and poll urlIsBlocked in case KVO doesn't fire.
        apply()
    }

    // MARK: Window

    /// Moves the one controller's view into a window for the current mode.
    private func placeWindow() {
        let old = window
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let frame: NSRect
        let preview = windowMode == .preview
        switch windowMode {
        case .pixel:
            frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 1, height: 1)
        case .preview:
            frame = NSRect(x: screen.visibleFrame.minX + 20, y: screen.visibleFrame.minY + 20, width: 320, height: 220)
        }
        let style: NSWindow.StyleMask = preview ? [.titled, .utilityWindow, .nonactivatingPanel, .resizable]
                                                : [.borderless, .nonactivatingPanel]
        let panel = NSPanel(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        panel.title = "Screen Time Bridge"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = preview ? .floating : .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = !preview
        panel.hasShadow = preview
        panel.alphaValue = preview ? 1 : 0
        panel.backgroundColor = preview ? .windowBackgroundColor : .clear
        panel.isOpaque = preview

        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        webpage.view.removeFromSuperview()
        webpage.view.frame = container.bounds
        webpage.view.autoresizingMask = [.width, .height]
        container.addSubview(webpage.view)
        panel.contentView = container
        panel.orderFrontRegardless()
        window = panel
        old?.orderOut(nil)
    }

    // MARK: Demo (snapshots only)

    func loadDemoState(_ demo: Status) {
        demoMode = true
        status = demo
        connectedBrowser = demo == .notConnected ? nil : .chrome
        ledger = ReportedLedger(day: ReportedLedger.today(),
                                seconds: ["youtube.com": 1_734, "reddit.com": 512, "github.com": 245])
        lastBlock = ("youtube.com", Date())
        if case .reporting(let url) = demo { reportingURL = url }
    }

    // MARK: Actions

    func resetLedger() {
        ledger = ReportedLedger(day: ReportedLedger.today())
        ledger.save()
    }

    func clearLog() { log.removeAll() }

    var logText: String {
        let f = ISO8601DateFormatter()
        return log.reversed().map { "\(f.string(from: $0.date)) [\($0.kind.rawValue)] \($0.message)" }.joined(separator: "\n")
    }

    private func record(_ kind: LogEntry.Kind, _ message: String) {
        logger.log("\(kind.rawValue, privacy: .public): \(message, privacy: .public)")
        log.insert(LogEntry(kind: kind, message: message), at: 0)
        if log.count > 300 { log.removeLast(log.count - 300) }
    }
}
