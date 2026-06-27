import Foundation
import Observation
@preconcurrency import WebKit

@Observable
@MainActor
public final class WebSceneBridge {
    public private(set) var isReady: Bool = false
    public private(set) var isRuntimeReady: Bool = false
    public private(set) var lastFPS: Double?
    public private(set) var lastError: String?
    public private(set) var isLoading: Bool = true

    @ObservationIgnored
    internal weak var webView: WKWebView?

    /// Strong reference to the custom-scheme router. WKWebViewConfiguration
    /// retains scheme handlers, but holding it on the bridge keeps the API
    /// surface symmetric with the WebView lifetime.
    @ObservationIgnored
    internal var router: WebSceneAssetRouter?

    @ObservationIgnored
    private var eventHandlers: [UUID: (WebSceneEvent) -> Void] = [:]

    @ObservationIgnored
    private var pendingCommands: [String] = []

    public init() {}

    public final class Subscription {
        fileprivate let id: UUID
        fileprivate weak var bridge: WebSceneBridge?

        fileprivate init(id: UUID, bridge: WebSceneBridge) {
            self.id = id
            self.bridge = bridge
        }

        @MainActor
        public func remove() {
            bridge?.eventHandlers.removeValue(forKey: id)
        }
    }

    @discardableResult
    public func onEvent(_ handler: @escaping (WebSceneEvent) -> Void) -> Subscription {
        let id = UUID()
        eventHandlers[id] = handler
        return Subscription(id: id, bridge: self)
    }

    public func send(type: String, payload: [String: Any] = [:]) {
        let envelope: [String: Any] = ["type": type, "payload": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope, options: []),
              let json = String(data: data, encoding: .utf8) else { return }
        let script = "window.__WebSceneRuntime && window.__WebSceneRuntime.dispatch(\(json));"
        dispatchScript(script)
    }

    public func evaluate(_ javascript: String) async throws -> Any? {
        guard let webView else { return nil }
        return try await webView.evaluateJavaScript(javascript)
    }

    // MARK: - Internal

    internal func attach(webView: WKWebView) {
        self.webView = webView
        flushPending()
    }

    internal func attach(router: WebSceneAssetRouter) {
        self.router = router
    }

    internal func handleIncoming(_ body: Any) {
        guard let dict = body as? [String: Any],
              let type = dict["type"] as? String else { return }

        switch type {
        case "__runtimeReady":
            isRuntimeReady = true
        case "__ready":
            isReady = true
            isLoading = false
            flushPending()
        case "__fps":
            if let payload = dict["payload"] as? [String: Any],
               let value = payload["value"] as? Double {
                lastFPS = value
            }
        case "__error":
            if let payload = dict["payload"] as? [String: Any],
               let message = payload["message"] as? String {
                lastError = message
            }
        case "__log":
            if let payload = dict["payload"] as? [String: Any],
               let level = payload["level"] as? String,
               let message = payload["message"] as? String {
                print("[WebScene/\(level)] \(message)")
            }
        default:
            break
        }

        let payloadAny = dict["payload"] ?? [String: Any]()
        let payloadDict = (payloadAny as? [String: Any]) ?? [:]
        var converted: [String: WebSceneValue] = [:]
        for (k, v) in payloadDict {
            converted[k] = WebSceneValue.from(v)
        }
        let event = WebSceneEvent(type: type, payload: converted)
        for handler in eventHandlers.values {
            handler(event)
        }
    }

    internal func reset() {
        isReady = false
        isLoading = true
        lastFPS = nil
    }

    private func dispatchScript(_ script: String) {
        guard let webView, isReady else {
            pendingCommands.append(script)
            return
        }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func flushPending() {
        guard let webView, isReady else { return }
        let queued = pendingCommands
        pendingCommands.removeAll()
        for script in queued {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}
