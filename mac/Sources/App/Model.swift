import Foundation

/// What the browser extension reports about the active tab.
struct TabReport: Decodable, Equatable {
    var type: String
    var browser: String?
    var url: String?
    var title: String?
    var tabId: Int?
    var windowFocused: Bool?
    var audible: Bool?
    var idle: String?

    var webURL: URL? {
        guard let url, let parsed = URL(string: url),
              let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return parsed
    }
}

enum Browser: String, CaseIterable, Identifiable {
    case chrome, firefox
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chrome: "Google Chrome"
        case .firefox: "Firefox"
        }
    }

    /// Bundle IDs that count as "this browser is frontmost".
    var bundleIDs: Set<String> {
        switch self {
        case .chrome: ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary"]
        case .firefox: ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"]
        }
    }

    static func from(bundleID: String?) -> Browser? {
        guard let bundleID else { return nil }
        return allCases.first { $0.bundleIDs.contains(bundleID) }
    }
}

/// Where the STWebpageController's view lives. Screen Time needs it in *some* window;
/// a 1×1 transparent one works as well as a visible one (spike S7).
enum BridgeWindowMode: String, CaseIterable, Identifiable {
    case pixel, preview
    var id: String { rawValue }

    var label: String {
        switch self {
        case .pixel: "Invisible (1-pixel window)"
        case .preview: "Visible preview"
        }
    }

    var help: String {
        switch self {
        case .pixel: "A transparent 1×1 point window. Screen Time still counts it as a page on screen."
        case .preview: "A small floating window that shows Screen Time's own view, including its block screen."
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let kind: Kind
    let message: String

    enum Kind: String { case info, report, blocked, error }
}

/// Seconds we told Screen Time about, per domain, for today. Lets you compare our
/// numbers with System Settings → Screen Time.
struct ReportedLedger: Codable {
    var day: String
    var seconds: [String: TimeInterval] = [:]

    static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func load() -> ReportedLedger {
        let today = today()
        if let data = UserDefaults.standard.data(forKey: "reportedLedger"),
           let ledger = try? JSONDecoder().decode(ReportedLedger.self, from: data),
           ledger.day == today {
            return ledger
        }
        return ReportedLedger(day: today)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "reportedLedger")
        }
    }

    mutating func add(_ interval: TimeInterval, to domain: String) {
        let today = Self.today()
        if day != today { self = ReportedLedger(day: today) }
        seconds[domain, default: 0] += interval
    }

    var top: [(domain: String, seconds: TimeInterval)] {
        seconds.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}

extension URL {
    /// "www.youtube.com" → "youtube.com". Good enough for display; not a real eTLD+1.
    var displayDomain: String {
        guard var host = host()?.lowercased() else { return absoluteString }
        for prefix in ["www.", "m.", "mobile."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        return host
    }
}

extension TimeInterval {
    var shortDuration: String {
        let s = Int(self)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }
}
