import Foundation
@preconcurrency import WebKit

@MainActor
public final class WebSceneCoordinator: NSObject {
    weak var bridge: WebSceneBridge?

    init(bridge: WebSceneBridge) {
        self.bridge = bridge
    }
}

extension WebSceneCoordinator: WKScriptMessageHandler {
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        bridge?.handleIncoming(message.body)
    }
}

extension WebSceneCoordinator: WKNavigationDelegate {
    public nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Ready signal is emitted from JS runtime once initialized.
    }

    public nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        let message = error.localizedDescription
        Task { @MainActor in
            bridge?.handleIncoming([
                "type": "__error",
                "payload": ["message": message]
            ])
        }
    }

    public nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        let message = error.localizedDescription
        Task { @MainActor in
            bridge?.handleIncoming([
                "type": "__error",
                "payload": ["message": message]
            ])
        }
    }
}

extension WebSceneCoordinator: WKUIDelegate {
    public nonisolated func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        return nil
    }
}
