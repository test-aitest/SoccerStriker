import SwiftUI
import AppKit

/// 代表チーム（国）。ユニフォーム色・国旗・名前を持つ。
/// 色は Three.js(pitch/select シーン)へ hex 文字列でそのまま渡す。
struct Country: Identifiable, Hashable {
    let id: String          // 国コード
    let name: String        // 表示名（日本語）
    let flag: String        // 国旗絵文字
    let primaryHex: String  // ユニフォーム主色
    let secondaryHex: String // 差し色
    /// バンドル内の国旗 SVG 名（Resources/flags/<name>.svg）。無い国は絵文字 `flag` で代用。
    let flagAsset: String?
    /// バンドル内の選手モデル画像名（Resources/teams/<name>.png）。用意がある国のみ。
    let playerAsset: String?

    var primaryColor: Color { Color(hex: primaryHex) }
    var secondaryColor: Color { Color(hex: secondaryHex) }
    /// 立ち姿の選手モデル画像（NSImage）。無ければ nil。
    var playerImage: NSImage? { teamImage(playerAsset) }
    /// シュートポーズ（カットイン用）。<asset>_shoot.png
    var shootImage: NSImage? { teamImage(playerAsset.map { "\($0)_shoot" }) }
    /// ドリブルポーズ（カットイン用）。<asset>_dribble.png
    var dribbleImage: NSImage? { teamImage(playerAsset.map { "\($0)_dribble" }) }
    /// 監督（采配的中カットイン用）。<asset>_director.png
    var directorImage: NSImage? { teamImage(playerAsset.map { "\($0)_director" }) }

    private func teamImage(_ name: String?) -> NSImage? {
        guard let name,
              let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "teams")
        else { return nil }
        return NSImage(contentsOf: url)
    }

    /// デモで使う代表 6 か国。選手モデル画像は用意できた国（日本/ブラジル）のみ。
    static let all: [Country] = [
        Country(id: "jp", name: "Japan",     flag: "🇯🇵", primaryHex: "#1b3aa0", secondaryHex: "#ffffff", flagAsset: "jp", playerAsset: "jp"),
        Country(id: "ar", name: "Argentina", flag: "🇦🇷", primaryHex: "#6cace4", secondaryHex: "#ffffff", flagAsset: "ar", playerAsset: nil),
        Country(id: "br", name: "Brazil",    flag: "🇧🇷", primaryHex: "#ffdf00", secondaryHex: "#2952c8", flagAsset: "br", playerAsset: "br"),
        Country(id: "es", name: "Spain",     flag: "🇪🇸", primaryHex: "#c60b1e", secondaryHex: "#ffc400", flagAsset: "es", playerAsset: nil),
        Country(id: "kr", name: "Korea",     flag: "🇰🇷", primaryHex: "#c8102e", secondaryHex: "#ffffff", flagAsset: "kr", playerAsset: nil),
        Country(id: "us", name: "USA",       flag: "🇺🇸", primaryHex: "#0a3161", secondaryHex: "#b31942", flagAsset: "us", playerAsset: nil),
    ]

    static let japan = all[0]
    static let brazil = all[2]
}

extension Color {
    /// "#rrggbb" から Color を作る。
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xff) / 255
        let g = Double((v >> 8) & 0xff) / 255
        let b = Double(v & 0xff) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
