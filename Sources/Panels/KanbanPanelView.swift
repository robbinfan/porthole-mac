import SwiftUI
import WebKit

struct KanbanPanelView: View {
    @ObservedObject var panel: KanbanPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void

    var body: some View {
        KanbanWebViewRepresentable(panel: panel)
    }
}

struct KanbanWebViewRepresentable: NSViewRepresentable {
    let panel: KanbanPanel

    func makeNSView(context: Context) -> WKWebView {
        panel.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
