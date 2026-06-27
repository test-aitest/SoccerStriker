import Foundation
@preconcurrency import WebKit

@MainActor
enum WebSceneRuntime {
    static func userScript(bridgeName: String) -> WKUserScript? {
        guard let url = Bundle.module.url(forResource: "WebSceneRuntime", withExtension: "js"),
              let template = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let escaped = bridgeName.replacingOccurrences(of: "\"", with: "\\\"")
        let source = template.replacingOccurrences(of: "__WEBSCENE_BRIDGE_NAME__", with: escaped)
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }
}
