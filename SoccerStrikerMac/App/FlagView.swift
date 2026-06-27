import SwiftUI
import AppKit

/// 国旗を表示する。バンドルに SVG があればそれを、無ければ絵文字を使う。
/// macOS の NSImage は SVG をネイティブに読み込める（macOS 13+）。
struct FlagView: View {
    let country: Country
    var height: CGFloat = 28

    var body: some View {
        if let img = Self.flagImage(country.flagAsset) {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.15), lineWidth: 0.5))
        } else {
            Text(country.flag)
                .font(.system(size: height * 0.9))
        }
    }

    /// バンドル Resources/flags/<name>.svg を NSImage で読む（キャッシュ付き）。
    private static var cache: [String: NSImage] = [:]
    private static func flagImage(_ name: String?) -> NSImage? {
        guard let name else { return nil }
        if let c = cache[name] { return c }
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "flags"),
              let img = NSImage(contentsOf: url) else { return nil }
        cache[name] = img
        return img
    }
}
