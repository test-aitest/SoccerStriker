import SwiftUI
import SoccerShared

/// iPhone コントローラのメイン画面。
/// 上部：アクション選択（シュート/パス/ヘッド/タックル）
/// 中央：「振って蹴る」ゾーン（蹴るとフラッシュ）
/// 下部：接続ステータス
struct KickView: View {
    @Bindable var client: NetworkClient
    @Bindable var motion: MotionStreamer

    @State private var flash: Double = 0
    @State private var score = "0 - 0"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Color.green.opacity(flash * 0.5).ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "figure.soccer")
                        .font(.system(size: 84))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("チャンス＆ピンチで\nこの iPhone を振る！")
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Text(score)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Mac 画面のゲージを見てタイミングよく")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                statusFooter
                    .padding(.bottom, 28)
            }
        }
        .onChange(of: motion.lastKick?.seq) { _, _ in
            guard motion.lastKick != nil else { return }
            withAnimation(.easeOut(duration: 0.07)) { flash = 1 }
            withAnimation(.easeIn(duration: 0.25).delay(0.07)) { flash = 0 }
        }
        .onChange(of: client.lastMessage) { _, msg in
            // "goal 1-0" のようなメッセージからスコアを拾う簡易表示
            let parts = msg.split(separator: " ")
            if let last = parts.last, last.contains("-") { score = last.replacingOccurrences(of: "-", with: " - ") }
        }
    }

    private var statusFooter: some View {
        VStack(spacing: 6) {
            if client.isConnected {
                Image(systemName: "wifi").font(.title2).foregroundStyle(.green)
            } else {
                VStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Mac を探しています...")
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
            Text(client.lastMessage)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
        }
    }
}
