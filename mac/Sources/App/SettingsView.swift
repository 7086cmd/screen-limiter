import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Bridge", systemImage: "point.3.connected.trianglepath.dotted") { BridgeSettings() }
            Tab("Diagnostics", systemImage: "stethoscope") { DiagnosticsView() }
        }
        .frame(width: 560, height: 500)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(Bridge.self) private var bridge
    @State private var refresh = 0
    @State private var installError: String?
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                ForEach(Browser.allCases) { browser in
                    BrowserRow(browser: browser,
                               connected: bridge.connectedBrowser == browser,
                               refresh: refresh) {
                        do {
                            try NativeHostInstaller.install(for: browser)
                            installError = nil
                        } catch {
                            installError = error.localizedDescription
                        }
                        refresh += 1
                    }
                }
                if let installError {
                    Text(installError).foregroundStyle(.red).font(.caption)
                }
            } header: {
                Text("Browsers")
            } footer: {
                Text("Safari reports to Screen Time by itself, so it needs no helper.")
                    .foregroundStyle(.secondary)
            }

            Section("Add the Chrome extension") {
                SetupStep(number: 1, text: "Open **chrome://extensions** in Chrome.") {
                    Button("Open") { open("chrome://extensions", in: .chrome) }
                        .disabled(!Browser.chrome.isInstalled)
                }
                SetupStep(number: 2, text: "Turn on **Developer mode** (top-right corner).")
                SetupStep(number: 3, text: "Click **Load unpacked** and choose the extension folder.") {
                    Button("Show Folder") { reveal(.chrome, file: nil) }
                }
            }

            Section {
                SetupStep(number: 1, text: "Open **about:debugging** → This Firefox.") {
                    Button("Open") { open("about:debugging#/runtime/this-firefox", in: .firefox) }
                        .disabled(!Browser.firefox.isInstalled)
                }
                SetupStep(number: 2, text: "Click **Load Temporary Add-on…** and choose **manifest.json**.") {
                    Button("Show File") { reveal(.firefox, file: "manifest.json") }
                }
            } header: {
                Text("Add the Firefox extension")
            } footer: {
                Text("Temporary add-ons are removed when Firefox quits. A permanent install needs the add-on signed by Mozilla.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Limits") {
                    Button("Open Screen Time Settings…") { SystemLinks.openScreenTimeSettings() }
                }
            } header: {
                Text("Screen Time")
            } footer: {
                Text("Add websites under App Limits in Screen Time. While Screen Limiter runs, Chrome time counts toward them, and Chrome tabs close when a limit is reached.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            openAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
    }

    private func open(_ address: String, in browser: Browser) {
        guard let app = browser.appURL, let url = URL(string: address) else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    private func reveal(_ browser: Browser, file: String?) {
        guard let folder = NativeHostInstaller.bundledExtensionFolder(for: browser) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file.map { folder.appending(path: $0) } ?? folder])
    }
}

private struct BrowserRow: View {
    let browser: Browser
    let connected: Bool
    let refresh: Int
    let install: () -> Void

    var body: some View {
        let _ = refresh  // re-read install state after Install/Reinstall
        let installed = browser.isInstalled
        let hostReady = NativeHostInstaller.isInstalled(for: browser)
        HStack(spacing: 10) {
            Image(nsImage: browser.icon)
                .resizable()
                .frame(width: 28, height: 28)
                .opacity(installed ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text(browser.displayName)
                Group {
                    if !installed {
                        Text("Not installed")
                    } else if connected {
                        Label("Extension connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if hostReady {
                        Text("Helper ready · waiting for the extension")
                    } else {
                        Text("Helper not installed")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if installed {
                Button(hostReady ? "Reinstall Helper" : "Install Helper", action: install)
            }
        }
    }
}

private struct SetupStep<Accessory: View>: View {
    let number: Int
    let text: LocalizedStringKey
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: .circle)
            Text(text)
            Spacer()
            accessory
        }
    }
}

extension SetupStep where Accessory == EmptyView {
    init(number: Int, text: LocalizedStringKey) {
        self.init(number: number, text: text) { EmptyView() }
    }
}

// MARK: - Bridge (experimental knobs for spike S7)

private struct BridgeSettings: View {
    @Environment(Bridge.self) private var bridge

    var body: some View {
        @Bindable var bridge = bridge
        Form {
            Section {
                Picker("Bridge window", selection: $bridge.windowMode) {
                    ForEach(BridgeWindowMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(bridge.windowMode.help)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $bridge.resubmitURL) {
                    Text("Re-check every 10 seconds")
                    Text("Screen Time checks limits when a URL is handed over, so a limit that runs out mid-page needs a re-check.")
                }
            } header: {
                Text("Bridge")
            } footer: {
                Text("Chrome time shows in Screen Time under “Screen Limiter”: only registered browsers may report under their own name.")
                    .foregroundStyle(.secondary)
            }

            Section("Live") {
                LabeledContent("Reporting") {
                    Text(bridge.reportingURL?.absoluteString ?? "—")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent("Screen Time verdict") {
                    if case .blocked = bridge.status {
                        Label("Blocked", systemImage: "hourglass.bottomhalf.filled").foregroundStyle(.red)
                    } else {
                        Text("Allowed")
                    }
                }
                LabeledContent("Last block") {
                    if let block = bridge.lastBlock {
                        Text("\(block.domain), \(block.date.formatted(date: .omitted, time: .shortened))")
                    } else {
                        Text("—")
                    }
                }
            }

            Section {
                if bridge.ledger.top.isEmpty {
                    Text("Nothing yet.").foregroundStyle(.secondary)
                }
                ForEach(bridge.ledger.top, id: \.domain) { item in
                    LabeledContent(item.domain) {
                        Text(item.seconds.shortDuration).monospacedDigit()
                    }
                }
            } header: {
                HStack {
                    Text("Sent to Screen Time today")
                    Spacer()
                    Button("Reset") { bridge.resetLedger() }
                        .controlSize(.small)
                }
            } footer: {
                Text("Compare these with System Settings → Screen Time → App & Website Activity.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Diagnostics

private struct DiagnosticsView: View {
    @Environment(Bridge.self) private var bridge

    var body: some View {
        VStack(spacing: 0) {
            List(bridge.log) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: entry.kind.symbol)
                        .foregroundStyle(entry.kind.color)
                        .frame(width: 14)
                    Text(entry.date, format: .dateTime.hour().minute().second())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(entry.message)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
                .font(.callout)
            }
            .overlay {
                if bridge.log.isEmpty {
                    ContentUnavailableView("No Events", systemImage: "stethoscope",
                                           description: Text("Switch tabs in Chrome to see reports."))
                }
            }
            Divider()
            HStack {
                Text("\(bridge.log.count) events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { bridge.clearLog() }
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bridge.logText, forType: .string)
                }
            }
            .padding(10)
        }
    }
}

private extension LogEntry.Kind {
    var symbol: String {
        switch self {
        case .info: "info.circle"
        case .report: "arrow.up.right.circle"
        case .blocked: "hourglass.bottomhalf.filled"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .info: .secondary
        case .report: .blue
        case .blocked: .red
        case .error: .orange
        }
    }
}
