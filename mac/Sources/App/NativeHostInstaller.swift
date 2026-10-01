import AppKit
import Foundation

/// Writes the native-messaging host manifests that let Chrome and Firefox launch
/// `ScreenLimiterHost` (bundled next to the app's main executable).
enum NativeHostInstaller {
    static let hostName = "dev.screenlimiter.host"
    /// Fixed by the `key` in extension/chrome/manifest.json.
    static let chromeExtensionID = "mbjjdikleafaggmieedmcbheipibhhfi"
    static let firefoxExtensionID = "screenlimiter@dev.screenlimiter"

    static var hostExecutable: URL? {
        Bundle.main.url(forAuxiliaryExecutable: "ScreenLimiterHost")
    }

    static func manifestDirectory(for browser: Browser) -> URL {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support")
        switch browser {
        case .chrome: return support.appending(path: "Google/Chrome/NativeMessagingHosts")
        case .firefox: return support.appending(path: "Mozilla/NativeMessagingHosts")
        }
    }

    static func manifestURL(for browser: Browser) -> URL {
        manifestDirectory(for: browser).appending(path: "\(hostName).json")
    }

    /// True if a manifest exists and points at this copy of the app.
    static func isInstalled(for browser: Browser) -> Bool {
        guard let data = try? Data(contentsOf: manifestURL(for: browser)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = json["path"] as? String
        else { return false }
        return path == hostExecutable?.path
    }

    @discardableResult
    static func install(for browser: Browser) throws -> URL {
        guard let host = hostExecutable else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "ScreenLimiterHost is missing from the app bundle."])
        }
        var manifest: [String: Any] = [
            "name": hostName,
            "description": "Screen Limiter bridge",
            "path": host.path,
            "type": "stdio",
        ]
        switch browser {
        case .chrome: manifest["allowed_origins"] = ["chrome-extension://\(chromeExtensionID)/"]
        case .firefox: manifest["allowed_extensions"] = [firefoxExtensionID]
        }
        let dir = manifestDirectory(for: browser)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        let url = manifestURL(for: browser)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// The unpacked extension shipped inside the app bundle.
    static func bundledExtensionFolder(for browser: Browser) -> URL? {
        switch browser {
        case .chrome: Bundle.main.url(forResource: "ChromeExtension", withExtension: nil)
        case .firefox: Bundle.main.url(forResource: "FirefoxExtension", withExtension: nil)
        }
    }
}
