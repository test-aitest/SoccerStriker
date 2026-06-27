import Foundation
import SoccerShared

/// Gemini 3.5 Flash を「戦術エージェント」として呼び、各選手の意図を決めさせる。
///
/// リアルタイム制約のため毎フレームではなく数秒ごとに呼ぶ。応答が来るまでは
/// エンジンが直前の意図を実行し続けるので試合は途切れない。
/// API キーは環境変数 `GEMINI_API_KEY`（無ければ UserDefaults "GeminiAPIKey"）から取得。
/// キーが無い／失敗時は nil を返し、呼び出し側はルールベースにフォールバックする。
actor AgentBrain {
    /// 使用モデル。I/O 2026 時点の最速エージェントモデル。
    private let model = "gemini-3.5-flash"
    private let session = URLSession(configuration: .ephemeral)

    private var apiKey: String? {
        // 1) ビルド時に Secrets.xcconfig → Info.plist へ注入された値（.env 相当）
        if let k = Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String,
           !k.isEmpty, !k.hasPrefix("$(") { return k }
        // 2) 環境変数（CI や一時上書き用）
        if let k = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !k.isEmpty { return k }
        // 3) UserDefaults（任意）
        if let k = UserDefaults.standard.string(forKey: "GeminiAPIKey"), !k.isEmpty { return k }
        return nil
    }

    var isConfigured: Bool { apiKey != nil }

    /// 局面の要約を渡し、AI が各選手に与える意図の配列を得る。失敗時 nil。
    func decide(prompt: String) async -> [Intention]? {
        guard let apiKey else { return nil }
        guard let url = URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")
        else { return nil }

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.8,
                "responseMimeType": "application/json",
                "responseSchema": Self.schema,
            ],
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 8
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                NSLog("[AgentBrain] HTTP error \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            // candidates[0].content.parts[0].text に JSON 配列文字列が入る
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cands = root["candidates"] as? [[String: Any]],
                  let content = cands.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String,
                  let jsonData = text.data(using: .utf8)
            else { return nil }
            return try? JSONDecoder().decode([Intention].self, from: jsonData)
        } catch {
            NSLog("[AgentBrain] request failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Gemini に返させる JSON 構造（意図の配列）。
    private static var schema: [String: Any] {[
        "type": "ARRAY",
        "items": [
            "type": "OBJECT",
            "properties": [
                "playerID": ["type": "INTEGER"],
                "action": ["type": "STRING",
                           "enum": ["move", "dribble", "shoot", "pass", "mark", "support", "hold"]],
                "targetX": ["type": "NUMBER"],
                "targetZ": ["type": "NUMBER"],
                "passTo": ["type": "INTEGER"],
            ],
            "required": ["playerID", "action", "targetX", "targetZ"],
        ],
    ]}
}
