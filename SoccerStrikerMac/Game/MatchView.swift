import SwiftUI
import WebSceneKit
import SoccerShared

/// 試合画面。Three.js のピッチを全面表示し、HUD とチャンスゲージを重ねる。
/// 両チームは AI が自動でプレイし、要所で人間のチャンスゲージが出る。
/// iPhone を振る（または Space キー）でチャンスに介入する。
struct MatchView: View {
    @Bindable var server: NetworkServer
    @State private var model: GameModel
    let onExit: () -> Void

    init(server: NetworkServer, onExit: @escaping () -> Void) {
        self.server = server
        self.onExit = onExit
        _model = State(initialValue: GameModel(server: server))
    }

    var body: some View {
        ZStack(alignment: .top) {
            WebSceneView(bridge: model.bridge, config: Self.sceneConfig)
                .ignoresSafeArea()

            scoreboard.padding(.top, 16)

            if let c = model.chance {
                ChanceOverlay(chance: c)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if !model.lastEventLabel.isEmpty {
                Text(model.lastEventLabel)
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(.white).shadow(radius: 12)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 960, minHeight: 600)
        .background(Color.black)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .onAppear { server.start(); model.start() }
        .onDisappear { model.stop(); server.stop() }
        .animation(.easeOut(duration: 0.2), value: model.chance == nil)
    }

    private var scoreboard: some View {
        HStack(spacing: 24) {
            teamScore("YOU", model.homeScore, .cyan)
            Text("VS").font(.headline).foregroundStyle(.white.opacity(0.5))
            teamScore("CPU", model.awayScore, .orange)
            Spacer()
            connectionBadge
        }
        .padding(.horizontal, 28).padding(.vertical, 12)
        .background(.black.opacity(0.45), in: Capsule())
        .padding(.horizontal, 24)
    }

    private func teamScore(_ name: String, _ score: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(name).font(.caption2.bold()).foregroundStyle(color)
            Text("\(score)").font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(.white)
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: server.isPhoneConnected ? "iphone.gen3" : "iphone.slash")
                .foregroundStyle(server.isPhoneConnected ? .green : .gray)
            Text(server.isPhoneConnected ? "接続中" : "キーボード(Space)")
                .font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .space:
            model.debugKick(); return .handled   // チャンス中の「振り」
        case .escape:
            onExit(); return .handled
        default:
            return .ignored
        }
    }

    private static var sceneConfig: WebSceneConfig {
        let webRoot = Bundle.main.resourceURL?.appendingPathComponent("web") ?? Bundle.main.bundleURL
        return WebSceneConfig(
            bundleURL: webRoot, indexFileName: "index.html",
            isTransparent: false, contentMode: .desktop,
            bridgeName: "WebScene", backgroundColorHex: "#0A0A0A"
        )
    }
}

// MARK: - チャンスゲージ

private struct ChanceOverlay: View {
    let chance: Chance

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(chance.title)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(chance.kind == .save ? .red : .yellow)
                .shadow(radius: 8)

            if let success = chance.success {
                Text(success ? "成功！" : "失敗")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(success ? .green : .white.opacity(0.8))
                    .shadow(radius: 10)
            } else {
                gauge
                Text("iPhone を振る / Space")
                    .font(.callout).foregroundStyle(.white.opacity(0.7))
            }
            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.35).ignoresSafeArea())
        .allowsHitTesting(false)
    }

    @ViewBuilder private var gauge: some View {
        switch chance.gauge {
        case .timing: timingGauge
        case .power:  powerGauge
        }
    }

    private var timingGauge: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                // 当たりゾーン
                Capsule().fill(.green.opacity(0.85))
                    .frame(width: w * CGFloat(chance.sweetHi - chance.sweetLo))
                    .offset(x: w * CGFloat(chance.sweetLo))
                // マーカー
                RoundedRectangle(cornerRadius: 3).fill(.white)
                    .frame(width: 6)
                    .offset(x: w * CGFloat(chance.progress) - 3)
                    .shadow(color: .white, radius: 6)
            }
        }
        .frame(width: 460, height: 26)
    }

    private var powerGauge: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    // 70% の成功ライン
                    Rectangle().fill(.white.opacity(0.6)).frame(width: 2)
                        .offset(x: w * 0.7)
                    Capsule()
                        .fill(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, w * CGFloat(chance.charge)))
                        .shadow(color: .orange.opacity(Double(chance.flash) * 4), radius: 12)
                }
            }
            .frame(width: 460, height: 26)
            Text("連打！").font(.headline.bold()).foregroundStyle(.orange)
                .scaleEffect(1 + CGFloat(chance.flash) * 1.5)
        }
    }
}
