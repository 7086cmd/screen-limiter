import SwiftUI

struct MenuView: View {
    @Environment(Bridge.self) private var bridge
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            NowCard(status: bridge.status, todaySeconds: todaySeconds, openSetup: showSettings)

            if !bridge.ledger.top.isEmpty {
                Divider().padding(.horizontal, 4)
                reportedToday
            }

            Divider().padding(.horizontal, 4)

            VStack(spacing: 0) {
                MenuRow("Screen Time Settings…", systemImage: "hourglass") {
                    SystemLinks.openScreenTimeSettings()
                }
                MenuRow("Settings…", systemImage: "gearshape", shortcut: "⌘,") {
                    showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                MenuRow("Quit Screen Limiter", systemImage: "power", shortcut: "⌘Q") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(10)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Screen Limiter")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var subtitle: String {
        if let browser = bridge.connectedBrowser { return "Connected to \(browser.displayName)" }
        return "Extension not connected"
    }

    private var todaySeconds: TimeInterval? {
        guard case .reporting(let url) = bridge.status else { return nil }
        return bridge.ledger.seconds[url.displayDomain]
    }

    private var reportedToday: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sent to Screen Time today")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(bridge.ledger.top.prefix(4), id: \.domain) { item in
                HStack {
                    Text(item.domain)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(item.seconds.shortDuration)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .padding(.horizontal, 6)
    }

    private func showSettings() {
        NSApp.activate()
        openSettings()
    }
}

// MARK: - Now card

private struct NowCard: View {
    let status: Bridge.Status
    let todaySeconds: TimeInterval?
    let openSetup: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(tint.gradient, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)

            if case .notConnected = status {
                Button("Set Up…", action: openSetup)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(.fill.quaternary, in: .rect(cornerRadius: 10))
        .animation(.snappy, value: status)
    }

    private var symbol: String {
        switch status {
        case .notConnected: "puzzlepiece.extension.fill"
        case .paused: "pause.fill"
        case .reporting: "dot.radiowaves.left.and.right"
        case .blocked: "hourglass.bottomhalf.filled"
        }
    }

    private var tint: Color {
        switch status {
        case .notConnected: .gray
        case .paused: .orange
        case .reporting: .green
        case .blocked: .red
        }
    }

    private var title: String {
        switch status {
        case .notConnected: "Not connected"
        case .paused: "Paused"
        case .reporting(let url): url.displayDomain
        case .blocked(let domain): domain
        }
    }

    private var detail: String {
        switch status {
        case .notConnected:
            "Add the Chrome extension to count browser time."
        case .paused(let reason):
            reason
        case .reporting:
            if let todaySeconds { "Counting in Screen Time · \(todaySeconds.shortDuration) today" }
            else { "Counting in Screen Time" }
        case .blocked:
            "Time limit reached. Screen Time blocked this site."
        }
    }
}

// MARK: - Menu-style row

private struct MenuRow: View {
    let title: String
    let systemImage: String
    var shortcut: String?
    let action: () -> Void

    init(_ title: String, systemImage: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(MenuRowStyle())
    }
}

private struct MenuRowStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(hovering ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
            }
            .onHover { hovering = $0 }
    }
}
