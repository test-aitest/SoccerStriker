import Foundation
@preconcurrency import WebKit

/// Custom-scheme URL router for `WebSceneView`.
///
/// Solves the WKWebView CORS limitation when loading scenes from `file://`:
/// `file://` documents have an *opaque* origin in WebKit, so any cross-origin
/// `fetch()` (Three.js GLTFLoader, Draco decoders, fonts, ...) is blocked unless
/// the remote server returns permissive `Access-Control-Allow-Origin` headers
/// for the `null` origin — which most CDNs do not.
///
/// `WebSceneAssetRouter` registers itself as a handler for a custom scheme
/// (e.g. `orepro://`) and serves both:
///
///   1. **Local bundled resources** under the configured bundle root (HTML / JS /
///      images / .glb files in `Resources/web/...`).
///
///   2. **Remote HTTPS resources** via a `/remote/<base64url>` path. The handler
///      decodes the base64url segment back into the original URL and proxies the
///      response through `URLSession`. Because the proxied response now appears
///      to come from the same custom-scheme origin as the page, the WebKit CORS
///      check is bypassed entirely.
///
/// The custom scheme also makes the document a *real* origin (`orepro://host/`)
/// rather than an opaque `null`, which fixes a class of subtle issues such as
/// `IndexedDB`, `localStorage`, `Service Worker`, and `WebGL2` features that
/// silently degrade under opaque origins.
///
/// ## Usage
///
/// Pass `customSchemeName: "orepro"` when constructing a `WebSceneConfig`.
/// `WebSceneHost` registers an instance of this router on the
/// `WKWebViewConfiguration` and loads the index via `customSchemeName:///<index>`
/// instead of `loadFileURL`.
///
/// ## URL conventions
///
/// | Path on the page | Resolves to |
/// |---|---|
/// | `orepro:///index.html` | `<bundleRoot>/index.html` |
/// | `orepro:///scene.bundle.js` | `<bundleRoot>/scene.bundle.js` |
/// | `orepro:///assets/title.glb` | `<bundleRoot>/assets/title.glb` |
/// | `orepro:///remote/aHR0c...nbGI` | base64url decode → `https://omma.build/.../foo.glb` |
/// | `orepro:///remote/aHR0c...zEuNy8/draco_decoder.js` | decode prefix → `https://www.gstatic.com/.../draco_decoder.js` |
///
/// The "split-prefix" form lets libraries that concatenate filenames onto a
/// directory (`DRACOLoader.setDecoderPath`) continue to work transparently:
/// only the prefix is encoded; the loader's appended filename is forwarded as-is.
@MainActor
public final class WebSceneAssetRouter: NSObject {

    /// Filesystem directory that backs local-resource lookups. Typically the
    /// `Resources/web/` directory inside the app bundle.
    public let bundleRoot: URL

    /// Custom URL scheme this router responds to (e.g. `"orepro"`).
    public let scheme: String

    /// Path prefix (with leading & trailing slash) that signals a remote proxy
    /// request. Anything that does not start with this prefix is served from
    /// `bundleRoot`. Default: `"/remote/"`.
    public let remotePathPrefix: String

    private let session: URLSession
    private var pendingTasks: [ObjectIdentifier: URLSessionDataTask] = [:]

    public init(
        bundleRoot: URL,
        scheme: String,
        remotePathPrefix: String = "/remote/"
    ) {
        self.bundleRoot = bundleRoot.standardizedFileURL
        self.scheme = scheme
        self.remotePathPrefix = remotePathPrefix

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .useProtocolCachePolicy
        self.session = URLSession(configuration: config)

        super.init()
    }

    /// Builds the entry-point URL the WebView should load. Equivalent to
    /// `<scheme>:///<indexFileName>`.
    public func indexURL(indexFileName: String) -> URL {
        URL(string: "\(scheme):///\(indexFileName)")!
    }
}

// MARK: - WKURLSchemeHandler

extension WebSceneAssetRouter: WKURLSchemeHandler {

    public nonisolated func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        // Hand the task across to the main actor for processing. Wrapping in
        // `Box` lets us silence Swift 6 strict concurrency warnings about
        // `WKURLSchemeTask` not being `Sendable` — WebKit guarantees thread
        // affinity in practice.
        let box = TaskBox(task: urlSchemeTask)
        let request = urlSchemeTask.request
        Task { @MainActor in
            self.dispatch(box: box, request: request)
        }
    }

    public nonisolated func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        let key = ObjectIdentifier(urlSchemeTask)
        Task { @MainActor in
            if let dt = self.pendingTasks.removeValue(forKey: key) {
                dt.cancel()
            }
        }
    }

    @MainActor
    private func dispatch(box: TaskBox, request: URLRequest) {
        let task = box.task
        guard let url = request.url else {
            fail(task: task, error: URLError(.badURL))
            return
        }
        let path = url.path

        if path.hasPrefix(remotePathPrefix) {
            let suffix = String(path.dropFirst(remotePathPrefix.count))
            guard let remoteURL = decodeRemoteURL(suffix) else {
                fail(task: task, error: URLError(.badURL))
                return
            }
            startRemoteFetch(box: box, remoteURL: remoteURL)
            return
        }

        startLocalFetch(task: task, requestURL: url, path: path)
    }

    // MARK: - Local fetch

    @MainActor
    private func startLocalFetch(task: any WKURLSchemeTask, requestURL: URL, path: String) {
        // Remove the leading slash to make it relative.
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let resolved = bundleRoot.appendingPathComponent(relative).standardizedFileURL

        // Sandbox check: prevent path traversal beyond the bundle root.
        guard resolved.path.hasPrefix(bundleRoot.path) else {
            fail(task: task, error: URLError(.noPermissionsToReadFile))
            return
        }
        guard FileManager.default.fileExists(atPath: resolved.path) else {
            send404(task: task, requestURL: requestURL)
            return
        }
        do {
            let data = try Data(contentsOf: resolved)
            let mime = mimeType(for: resolved.pathExtension)
            let response = HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": mime,
                    "Content-Length": String(data.count),
                    "Access-Control-Allow-Origin": "*",
                    "Cache-Control": "public, max-age=3600",
                ]
            )!
            send(task: task, response: response, data: data)
        } catch {
            fail(task: task, error: error)
        }
    }

    // MARK: - Remote fetch (proxy)

    @MainActor
    private func startRemoteFetch(box: TaskBox, remoteURL: URL) {
        let task = box.task
        let key = ObjectIdentifier(task)
        let requestURL = task.request.url ?? remoteURL

        var req = URLRequest(url: remoteURL)
        req.cachePolicy = .useProtocolCachePolicy
        req.setValue("application/octet-stream, model/gltf-binary, */*", forHTTPHeaderField: "Accept")

        let dataTask = session.dataTask(with: req) { [weak self] data, response, error in
            // The URLSession callback runs on a background queue; re-enter
            // MainActor and use the boxed (un-Sendable) WKURLSchemeTask there.
            let captured = box
            Task { @MainActor in
                guard let self else { return }
                guard self.pendingTasks.removeValue(forKey: key) != nil else { return }
                let task = captured.task

                if let error {
                    self.fail(task: task, error: error)
                    return
                }
                guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                    self.fail(task: task, error: URLError(.badServerResponse))
                    return
                }

                var headers: [String: String] = [:]
                for (k, v) in httpResponse.allHeaderFields {
                    if let key = k as? String, let val = v as? String {
                        headers[key] = val
                    }
                }
                headers["Access-Control-Allow-Origin"] = "*"
                headers.removeValue(forKey: "Content-Security-Policy")
                headers.removeValue(forKey: "content-security-policy")

                let proxied = HTTPURLResponse(
                    url: requestURL,
                    statusCode: httpResponse.statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: headers
                )!
                self.send(task: task, response: proxied, data: data)
            }
        }
        pendingTasks[key] = dataTask
        dataTask.resume()
    }

    // MARK: - Task lifecycle helpers

    @MainActor
    private func send(task: any WKURLSchemeTask, response: URLResponse, data: Data) {
        // WKURLSchemeTask methods raise an Obj-C exception if called after the
        // task has been stopped. We can't catch ObjC exceptions natively, so
        // we rely on the pendingTasks dictionary as the canonical source of
        // truth and tolerate the race window for the synchronous local path.
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    @MainActor
    private func fail(task: any WKURLSchemeTask, error: Error) {
        task.didFailWithError(error)
    }

    @MainActor
    private func send404(task: any WKURLSchemeTask, requestURL: URL) {
        let response = HTTPURLResponse(
            url: requestURL,
            statusCode: 404,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/plain"]
        )!
        let body = Data("Not Found".utf8)
        send(task: task, response: response, data: body)
    }

    // MARK: - Encoding helpers

    /// Decode a `/remote/...` path suffix into the remote URL.
    ///
    /// Two forms are supported:
    /// - `<base64url>`           → full URL encoded
    /// - `<base64url>/<rest...>` → encoded prefix, with `<rest>` appended verbatim
    ///
    /// The split form lets libraries that internally concatenate filenames onto
    /// a directory path (e.g. `DRACOLoader.setDecoderPath`) keep working: only
    /// the prefix is encoded.
    private func decodeRemoteURL(_ suffix: String) -> URL? {
        // Find the first '/' separating the encoded prefix from the appended tail.
        if let slashIndex = suffix.firstIndex(of: "/") {
            let prefixToken = String(suffix[..<slashIndex])
            let tail = String(suffix[suffix.index(after: slashIndex)...])
            guard let prefixURL = decodeBase64URL(prefixToken) else { return nil }
            // Concatenate as raw strings so prefix's trailing slash semantics are
            // preserved.
            return URL(string: prefixURL + tail)
        }
        guard let urlStr = decodeBase64URL(suffix) else { return nil }
        return URL(string: urlStr)
    }

    /// URL-safe base64 → UTF-8 string. Tolerates missing `=` padding.
    private func decodeBase64URL(_ token: String) -> String? {
        var s = token
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = s.count % 4
        if pad > 0 { s.append(String(repeating: "=", count: 4 - pad)) }
        guard let data = Data(base64Encoded: s) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// `WKURLSchemeTask` is not `Sendable` in Swift 6, but WebKit guarantees
    /// the calls happen on the same thread that started them. We hop to
    /// `@MainActor` for processing; this box is a small `@unchecked Sendable`
    /// shim that lets us pass the task across the actor hop without warnings.
    private struct TaskBox: @unchecked Sendable {
        let task: any WKURLSchemeTask
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm":  return "text/html; charset=utf-8"
        case "js", "mjs":    return "application/javascript; charset=utf-8"
        case "css":          return "text/css; charset=utf-8"
        case "json":         return "application/json; charset=utf-8"
        case "glb":          return "model/gltf-binary"
        case "gltf":         return "model/gltf+json"
        case "png":          return "image/png"
        case "jpg", "jpeg":  return "image/jpeg"
        case "webp":         return "image/webp"
        case "svg":          return "image/svg+xml"
        case "ico":          return "image/x-icon"
        case "wasm":         return "application/wasm"
        case "woff2":        return "font/woff2"
        case "woff":         return "font/woff"
        case "ttf":          return "font/ttf"
        case "otf":          return "font/otf"
        case "mp3":          return "audio/mpeg"
        case "wav":          return "audio/wav"
        case "ogg":          return "audio/ogg"
        case "mp4":          return "video/mp4"
        default:             return "application/octet-stream"
        }
    }
}
