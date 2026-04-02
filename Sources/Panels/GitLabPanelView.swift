import SwiftUI
import WebKit

struct GitLabPanelView: View {
    @ObservedObject var panel: GitLabPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void

    var body: some View {
        GitLabWebViewRepresentable(panel: panel)
            .onAppear { panel.injectToken() }
    }
}

struct GitLabWebViewRepresentable: NSViewRepresentable {
    let panel: GitLabPanel

    func makeNSView(context: Context) -> WKWebView {
        panel.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
