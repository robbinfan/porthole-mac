import AppKit
import WebKit
import Combine

@MainActor
final class GitLabPanel: NSObject, Panel, ObservableObject {
    let id = UUID()
    let panelType: PanelType = .gitlab

    @Published var displayTitle: String = "GitLab"
    var displayIcon: String? { "arrow.triangle.branch" }

    private(set) var webView: WKWebView!
    private var gitlabConfig: GitLabConfig?

    override init() {
        super.init()
        setupWebView()
        loadGitLabConfig()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = true
        self.webView = webView

        loadPanel()
    }

    private func loadPanel() {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "panels/gitlab") else {
            webView.loadHTMLString("<h1>GitLab panel resources not found</h1>", baseURL: nil)
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    private func loadGitLabConfig() {
        gitlabConfig = GitLabConfig.load()
    }

    func injectToken() {
        guard let config = gitlabConfig, let token = config.loadToken() else { return }
        let escapedHost = config.host.replacingOccurrences(of: "'", with: "\\'")
        let escapedToken = token.replacingOccurrences(of: "'", with: "\\'")
        let js = """
        window.__GITLAB_HOST__ = '\(escapedHost)';
        window.__GITLAB_TOKEN__ = '\(escapedToken)';
        window.__GITLAB_READY__ = true;
        if (typeof window.onGitLabReady === 'function') window.onGitLabReady();
        """
        webView.evaluateJavaScript(js)
    }

    func close() {}

    func focus() {
        webView.window?.makeFirstResponder(webView)
    }

    func unfocus() {}

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {}
}
