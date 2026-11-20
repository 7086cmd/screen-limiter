import CryptoKit
import Foundation
import Security

/// What the "Time Limit Reached" page can ask for, mirroring Screen Time's own choices.
enum ExtraTimeOption: String, CaseIterable, Decodable {
    case oneMinute, fifteenMinutes, oneHour, allDay

    /// Everything past "One More Minute" needs the passcode, when one is set.
    var needsPasscode: Bool { self != .oneMinute }

    var label: String {
        switch self {
        case .oneMinute: "1 minute"
        case .fifteenMinutes: "15 minutes"
        case .oneHour: "1 hour"
        case .allDay: "the rest of today"
        }
    }

    func until(from now: Date = Date()) -> Date {
        switch self {
        case .oneMinute: now.addingTimeInterval(60)
        case .fifteenMinutes: now.addingTimeInterval(15 * 60)
        case .oneHour: now.addingTimeInterval(60 * 60)
        case .allDay: Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)
        }
    }
}

/// Extra time granted from the block page, per domain, for today. Screen Time itself still
/// says the site is over its limit; the bridge just doesn't block it until the grant runs out.
struct ExtraTime: Codable {
    var day: String
    var grants: [String: Date] = [:]
    /// Like Screen Time, "One More Minute" works once per site per day.
    var usedOneMinute: Set<String> = []

    static func load() -> ExtraTime {
        let today = ReportedLedger.today()
        if let data = UserDefaults.standard.data(forKey: "extraTime"),
           let saved = try? JSONDecoder().decode(ExtraTime.self, from: data),
           saved.day == today {
            return saved
        }
        return ExtraTime(day: today)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "extraTime")
        }
    }

    func until(for domain: String, now: Date = Date()) -> Date? {
        guard day == ReportedLedger.today(), let until = grants[domain], until > now else { return nil }
        return until
    }

    func canUseOneMinute(_ domain: String) -> Bool {
        day != ReportedLedger.today() || !usedOneMinute.contains(domain)
    }

    mutating func grant(_ option: ExtraTimeOption, to domain: String) -> Date {
        let today = ReportedLedger.today()
        if day != today { self = ExtraTime(day: today) }
        if option == .oneMinute { usedOneMinute.insert(domain) }
        let until = max(option.until(), grants[domain] ?? .distantPast)
        grants[domain] = until
        return until
    }
}

/// The passcode that unlocks 15 minutes / 1 hour / all day. Only its SHA-256 is stored,
/// in the login keychain. (Screen Time's own passcode can't be checked by other apps.)
enum Passcode {
    private static let service = "dev.screenlimiter.passcode"
    private static let account = "extra-time"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func hash(_ passcode: String) -> Data {
        Data(SHA256.hash(data: Data(passcode.utf8)))
    }

    private static var stored: Data? {
        var q = query
        q[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static var isSet: Bool { stored != nil }

    static func verify(_ passcode: String?) -> Bool {
        guard let stored else { return true }
        guard let passcode else { return false }
        return hash(passcode) == stored
    }

    @discardableResult
    static func set(_ passcode: String) -> Bool {
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = hash(passcode)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        SecItemDelete(query as CFDictionary)
    }
}
