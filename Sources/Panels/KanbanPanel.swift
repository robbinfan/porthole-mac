import AppKit
import WebKit
import Combine

@MainActor
final class KanbanPanel: NSObject, Panel, ObservableObject {
    let id = UUID()
    let panelType: PanelType = .kanban

    @Published var displayTitle: String = "Agents"
    var displayIcon: String? { "person.2" }

    private(set) var webView: WKWebView!
    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 3.0

    override init() {
        super.init()
        setupWebView()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Add message handler for Focus/Stop actions from JS
        let handler = KanbanMessageHandler(panel: self)
        config.userContentController.add(handler, name: "cmux")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = true
        self.webView = webView

        loadPanel()
        startPolling()
    }

    private func loadPanel() {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "panels/kanban") else {
            webView.loadHTMLString("<h1>Kanban panel resources not found</h1>", baseURL: nil)
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.detectAgents()
            }
        }
    }

    func detectAgents() {
        // Stub — will be wired to real terminal surfaces in Task 15
        // For now, push empty array to keep frontend alive
        pushAgentState("[]")
    }

    func pushAgentState(_ json: String) {
        let js = "if (typeof window.updateAgents === 'function') window.updateAgents(\(json));"
        webView.evaluateJavaScript(js)
    }

    func close() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func focus() {
        webView.window?.makeFirstResponder(webView)
    }

    func unfocus() {}

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {}
}

// MARK: - Message Handler for JS → Swift communication

class KanbanMessageHandler: NSObject, WKScriptMessageHandler {
    weak var panel: KanbanPanel?

    init(panel: KanbanPanel) {
        self.panel = panel
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: String],
              let action = body["action"],
              let paneId = body["paneId"] else { return }

        // Will be wired to TerminalController in Task 15
        switch action {
        case "focus-pane":
            // TerminalController.shared.focusSurface(UUID(uuidString: paneId))
            break
        case "send-key":
            // TerminalController.shared.sendKey(to: UUID(uuidString: paneId), key: "C-c")
            break
        default:
            break
        }
    }
}
