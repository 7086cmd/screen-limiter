// ScreenLimiterHost — Chrome/Firefox native-messaging host.
//
// The browser launches this binary and talks to it over stdin/stdout using
// 4-byte little-endian length-prefixed JSON. We relay every message to the
// menu-bar app through distributed notifications, and relay the app's replies
// back to the extension.

import AppKit
import Foundation

let fromExtension = Notification.Name("dev.screenlimiter.fromExtension")
let toExtension = Notification.Name("dev.screenlimiter.toExtension")
let center = DistributedNotificationCenter.default()
let stdout = FileHandle.standardOutput
let writeLock = NSLock()

func post(_ json: String) {
    center.postNotificationName(fromExtension, object: json, userInfo: nil, deliverImmediately: true)
}

func send(_ json: String) {
    guard let body = json.data(using: .utf8) else { return }
    var length = UInt32(body.count).littleEndian
    writeLock.lock()
    defer { writeLock.unlock() }
    stdout.write(Data(bytes: &length, count: 4))
    stdout.write(body)
}

/// This executable lives in ScreenLimiter.app/Contents/MacOS, so Bundle.main is the app.
func launchAppIfNeeded() {
    let appURL = Bundle.main.bundleURL
    guard appURL.pathExtension == "app",
          let bundleID = Bundle.main.bundleIdentifier,
          NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    else { return }
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    NSWorkspace.shared.openApplication(at: appURL, configuration: config)
}

center.addObserver(forName: toExtension, object: nil, queue: .main) { note in
    if let json = note.object as? String { send(json) }
}

launchAppIfNeeded()
post(#"{"type":"hostConnected"}"#)

Thread.detachNewThread {
    let stdin = FileHandle.standardInput
    while true {
        let header = stdin.readData(ofLength: 4)
        guard header.count == 4 else { break }
        let length = header.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        let body = stdin.readData(ofLength: length)
        guard body.count == length, let json = String(data: body, encoding: .utf8) else { break }
        post(json)
    }
    // Browser closed the port (extension reloaded or browser quit).
    post(#"{"type":"hostDisconnected"}"#)
    DispatchQueue.main.async { exit(0) }
}

RunLoop.main.run()
