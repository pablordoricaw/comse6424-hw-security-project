import TUIkit
import LicenseGate
import Foundation
import PromptPipeline

public nonisolated(unsafe) var sharedLicenseInfo: LicenseInfo? = nil
public nonisolated(unsafe) var sharedAssetStore: AssetStore? = nil

public struct TUIRenderer: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            PromptView()
        }
    }
}

struct PromptView: View {

    private let licenseInfo: LicenseInfo

    init() {
        self.licenseInfo = sharedLicenseInfo!
    }

    @Environment(\.statusBar) private var statusBar

    @State private var input: String = ""
    @State private var scrollOffset: Int = 0
    @State private var outputLines: [String] = ["Type /help for available commands."]
    @State private var viewportHeight: Int = 0  // tracked at render time
    @State private var activeTask: Task<Void, Never>? = nil

    var body: some View {
        statusBar.showSystemItems = false

        return VStack(alignment: .leading, spacing: 0) {
            ScrollableText(lines: outputLines, offset: $scrollOffset, onViewportHeight: { h in
                viewportHeight = h
            })

            HStack(spacing: 0) {
                Text("> ").foregroundStyle(.palette.accent)
                TextField("", text: $input, prompt: Text(""))
                    .onSubmit {
                        handleInput(input)
                        input = ""
                        scrollOffset = 0
                    }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .appHeader {
            HStack {
                Text("CloseCode").bold()
                Spacer()
                Text("Licensed").foregroundStyle(.palette.accent)
            }
        }
        .onKeyPress { event in
            switch (event.key, event.ctrl, event.shift) {

            // Arrow keys
            case (.up, _, _):
                scrollOffset = max(0, scrollOffset - 1)
                return true
            case (.down, _, _):
                scrollOffset = min(maxOffset, scrollOffset + 1)
                return true

            // Ctrl+K — up 1
            case (.character("k"), true, _):
                scrollOffset = max(0, scrollOffset - 1)
                return true

            // Ctrl+J is 0x0A (line feed) — the terminal never sends it as .character("j")
            // Use Ctrl+L for down 1 instead (safe, no terminal conflict)
            case (.character("l"), true, _):
                scrollOffset = min(maxOffset, scrollOffset + 1)
                return true

            // Ctrl+U — half page up
            case (.character("u"), true, _):
                scrollOffset = max(0, scrollOffset - (viewportHeight / 2))
                return true

            // Ctrl+D — half page down
            case (.character("d"), true, _):
                scrollOffset = min(maxOffset, scrollOffset + (viewportHeight / 2))
                return true

            // Ctrl+G (lowercase) — jump to bottom
            case (.character("g"), true, false):
                scrollOffset = maxOffset
                return true

            // Ctrl+Shift+G (you're pressing this for capital G) — jump to top
            case (.character("g"), true, true):
                scrollOffset = 0
                return true

            default:
                return false
            }
        }
    }

    // The furthest offset where the last page is still full
    private var maxOffset: Int {
        max(0, outputLines.count - viewportHeight)
    }

    private func handleInput(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        scrollOffset = 0

        switch trimmed {
        case "/exit":
            exit(0)

        case "/help":
            outputLines = [
                "CloseCode - Hardware-Locked AI Code Assistant",
                "  License is bound to this device via the Secure Enclave.",
                "  The master AES key never exists in plaintext on disk.",
                "",
                "Commands:",
                "  /help    Show this message",
                "  /status  Show license details",
                "  /exit    Quit CloseCode",
                "  <prompt> Submit a prompt (Phase 2: not yet implemented)",
            ]

        case "/status":
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            outputLines = [
                "License Status:",
                "  Device:  \(licenseInfo.deviceFingerprint)",
                "  Expires: \(formatter.string(from: licenseInfo.expirationDate))",
                "  SE Key:  Active",
            ]

        case "/clear":
            outputLines = ["Type /help for available commands."]

        default:
            do {
                let pipeline = PromptPipeline(assets: sharedAssetStore!)
                let enriched = try pipeline.process(userQuery: trimmed)
                outputLines = ["[Pipeline ready]"] + enriched.rendered
                    .components(separatedBy: "\n")
            } catch {
                outputLines = ["Pipeline error: \(error.localizedDescription)"]
            }
        }
    }
}
