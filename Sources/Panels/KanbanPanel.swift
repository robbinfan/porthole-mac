import AppKit
import WebKit
import Combine

/// Represents a detected agent from a terminal panel
struct DetectedAgent: Codable {
    let panelId: String
    let paneId: String?
    let title: String
    let agentType: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case panelId = "panel_id"
        case paneId = "pane_id"
        case title
        case agentType = "agent_type"
        case status
    }
}

@MainActor
final class KanbanPanel: NSObject, Panel, ObservableObject {
    let id = UUID()
    let panelType: PanelType = .kanban

    @Published var displayTitle: String = "Agents"
    var displayIcon: String? { "person.2" }

    private(set) var webView: WKWebView!
    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 3.0

    /// Closure provided by Workspace to scan terminal panels for agent status.
    /// Returns an array of DetectedAgent structs.
    var agentScanner: (() -> [DetectedAgent])?

    override init() {
        super.init()
        setupWebView()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

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
        let agents = agentScanner?() ?? []
        guard let jsonData = try? JSONEncoder().encode(agents),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            pushAgentState("[]")
            return
        }
        pushAgentState(jsonString)
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
              let panelIdStr = body["paneId"],
              let panelId = UUID(uuidString: panelIdStr) else { return }

        Task { @MainActor in
            switch action {
            case "focus-pane":
                NotificationCenter.default.post(
                    name: .kanbanFocusPanel,
                    object: nil,
                    userInfo: ["panelId": panelId]
                )
            case "stop-agent":
                NotificationCenter.default.post(
                    name: .kanbanInterruptPanel,
                    object: nil,
                    userInfo: ["panelId": panelId]
                )
            default:
                break
            }
        }
    }
}

extension Notification.Name {
    static let kanbanFocusPanel = Notification.Name("kanbanFocusPanel")
    static let kanbanInterruptPanel = Notification.Name("kanbanInterruptPanel")
}
