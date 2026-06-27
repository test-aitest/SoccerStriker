import Foundation

public struct WebSceneConfig: Sendable {
    public enum ContentMode: Sendable {
        case mobile
        case desktop
    }

    public var bundleURL: URL
    public var indexFileName: String
    public var allowedReadRoot: URL?
    public var isTransparent: Bool
    public var allowsScrolling: Bool
    public var allowsZoom: Bool
    public var allowsLinkPreview: Bool
    public var suppressesIncrementalRendering: Bool
    public var contentMode: ContentMode
    public var bridgeName: String
    public var userAgentSuffix: String?
    public var developerExtrasEnabled: Bool
    public var backgroundColorHex: String?
    /// Optional custom URL scheme. When set, the scene is loaded via
    /// `WebSceneAssetRouter` (a `WKURLSchemeHandler`) instead of `loadFileURL`,
    /// granting the page a *real* origin that allows cross-origin `fetch()` to
    /// work via a `/remote/<base64url>` proxy path. Use this for scenes that
    /// load remote `.glb` models, Draco decoders, web fonts, etc.
    /// Reserved schemes (`http`, `https`, `file`, `about`, `data`, `blob`,
    /// `javascript`, `ws`, `wss`) cannot be used. Example: `"orepro"`.
    public var customSchemeName: String?

    public init(
        bundleURL: URL,
        indexFileName: String = "index.html",
        allowedReadRoot: URL? = nil,
        isTransparent: Bool = false,
        allowsScrolling: Bool = false,
        allowsZoom: Bool = false,
        allowsLinkPreview: Bool = false,
        suppressesIncrementalRendering: Bool = false,
        contentMode: ContentMode = .mobile,
        bridgeName: String = "WebScene",
        userAgentSuffix: String? = "WebSceneKit/1.0",
        developerExtrasEnabled: Bool = false,
        backgroundColorHex: String? = nil,
        customSchemeName: String? = nil
    ) {
        self.bundleURL = bundleURL
        self.indexFileName = indexFileName
        self.allowedReadRoot = allowedReadRoot ?? bundleURL
        self.isTransparent = isTransparent
        self.allowsScrolling = allowsScrolling
        self.allowsZoom = allowsZoom
        self.allowsLinkPreview = allowsLinkPreview
        self.suppressesIncrementalRendering = suppressesIncrementalRendering
        self.contentMode = contentMode
        self.bridgeName = bridgeName
        self.userAgentSuffix = userAgentSuffix
        self.developerExtrasEnabled = developerExtrasEnabled
        self.backgroundColorHex = backgroundColorHex
        self.customSchemeName = customSchemeName
    }

    public var indexURL: URL {
        bundleURL.appendingPathComponent(indexFileName)
    }
}
