import SwiftUI
@preconcurrency import WebKit

#if canImport(UIKit)
import UIKit
public typealias PlatformViewRepresentable = UIViewRepresentable
#elseif canImport(AppKit)
import AppKit
public typealias PlatformViewRepresentable = NSViewRepresentable
#endif

@MainActor
public struct WebSceneHost: PlatformViewRepresentable {
    let bridge: WebSceneBridge
    let config: WebSceneConfig

    public init(bridge: WebSceneBridge, config: WebSceneConfig) {
        self.bridge = bridge
        self.config = config
    }

    public func makeCoordinator() -> WebSceneCoordinator {
        WebSceneCoordinator(bridge: bridge)
    }

    #if canImport(UIKit)
    public func makeUIView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}
    #elseif canImport(AppKit)
    public func makeNSView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {}
    #endif

    private func makeWebView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()

        if let runtimeScript = WebSceneRuntime.userScript(bridgeName: config.bridgeName) {
            contentController.addUserScript(runtimeScript)
        }

        contentController.add(context.coordinator, name: config.bridgeName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        // Register the custom-scheme asset router *before* the WKWebView is
        // created, because WKWebViewConfiguration freezes scheme handlers at
        // init time. Holding the router on the bridge keeps it alive for the
        // lifetime of the WebView.
        if let scheme = config.customSchemeName, !scheme.isEmpty {
            let bundleRoot = config.allowedReadRoot ?? config.bundleURL
            let router = WebSceneAssetRouter(bundleRoot: bundleRoot, scheme: scheme)
            configuration.setURLSchemeHandler(router, forURLScheme: scheme)
            bridge.attach(router: router)
        }
        #if canImport(UIKit)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        #endif
        configuration.suppressesIncrementalRendering = config.suppressesIncrementalRendering

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        prefs.preferredContentMode = config.contentMode == .desktop ? .desktop : .mobile
        configuration.defaultWebpagePreferences = prefs

        let pagePrefs = configuration.preferences
        pagePrefs.javaScriptCanOpenWindowsAutomatically = false
        if #available(iOS 16.4, macOS 13.3, *) {
            pagePrefs.isElementFullscreenEnabled = false
            #if DEBUG
            pagePrefs.setValue(config.developerExtrasEnabled, forKey: "developerExtrasEnabled")
            #endif
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        if #available(iOS 16.4, macOS 13.3, visionOS 1.0, *) {
            #if DEBUG
            webView.isInspectable = config.developerExtrasEnabled
            #endif
        }

        // Smoothness optimizations
        #if canImport(UIKit)
        if config.isTransparent {
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
        } else {
            webView.isOpaque = true
            if let hex = config.backgroundColorHex, let color = UIColor(hex: hex) {
                webView.backgroundColor = color
                webView.scrollView.backgroundColor = color
                webView.underPageBackgroundColor = color
            }
        }
        #endif

        #if canImport(UIKit)
        webView.scrollView.isScrollEnabled = config.allowsScrolling
        webView.scrollView.bounces = false
        webView.scrollView.bouncesZoom = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.pinchGestureRecognizer?.isEnabled = config.allowsZoom
        webView.allowsLinkPreview = config.allowsLinkPreview
        webView.allowsBackForwardNavigationGestures = false
        #endif

        if let suffix = config.userAgentSuffix {
            webView.customUserAgent = "\(defaultUserAgent()) \(suffix)"
        }

        bridge.attach(webView: webView)
        bridge.reset()
        loadContent(into: webView)

        return webView
    }

    private func loadContent(into webView: WKWebView) {
        // Custom scheme path: load via the asset router so the document gets a
        // real, non-opaque origin (and cross-origin fetches go through the
        // `/remote/` proxy).
        if let router = bridge.router {
            let url = router.indexURL(indexFileName: config.indexFileName)
            webView.load(URLRequest(url: url))
            return
        }
        // Fallback: classic file:// loading with a read-access scope.
        let indexURL = config.indexURL
        let readRoot = config.allowedReadRoot ?? config.bundleURL
        webView.loadFileURL(indexURL, allowingReadAccessTo: readRoot)
    }

    private func defaultUserAgent() -> String {
        #if canImport(UIKit)
        return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1"
        #else
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15"
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        guard hexString.count == 6 || hexString.count == 8 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: hexString).scanHexInt64(&value) else { return nil }
        let r, g, b, a: CGFloat
        if hexString.count == 6 {
            r = CGFloat((value & 0xFF0000) >> 16) / 255
            g = CGFloat((value & 0x00FF00) >> 8) / 255
            b = CGFloat(value & 0x0000FF) / 255
            a = 1.0
        } else {
            r = CGFloat((value & 0xFF000000) >> 24) / 255
            g = CGFloat((value & 0x00FF0000) >> 16) / 255
            b = CGFloat((value & 0x0000FF00) >> 8) / 255
            a = CGFloat(value & 0x000000FF) / 255
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
#endif
