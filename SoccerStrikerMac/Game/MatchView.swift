import SwiftUI
import WebSceneKit
import SoccerShared

/// 試合画面。Three.js のピッチを全面表示し、HUD とチャンスゲージを重ねる。
/// 両チームは AI が自動でプレイし、要所で人間のチャンスゲージが出る。
/// iPhone を振る（または Space キー）でチャンスに介入する。
struct MatchView: View {
    @Bindable var server: NetworkServer
    @State private var model: GameModel
    let home: Country
    let away: Country
    let onExit: () -> Void

    init(server: NetworkServer, home: Country, away: Country, onExit: @escaping () -> Void) {
        self.server = server
        self.home = home
        self.away = away
        self.onExit = onExit
        _model = State(initialValue: GameModel(server: server, home: home, away: away))
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

            // 横からスライドインするカットイン（シュート/ドリブル）。
            if let cut = model.cutIn {
                CutInView(cut: cut)
                    .id(cut.id)
                    .transition(.move(edge: cut.fromLeft ? .leading : .trailing).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.cutIn?.id)
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
            teamScore(home, model.homeScore)
            Text("VS").font(.headline).foregroundStyle(.white.opacity(0.5))
            teamScore(away, model.awayScore)
            Spacer()
            aiBadge
            connectionBadge
        }
        .padding(.horizontal, 28).padding(.vertical, 12)
        .background(.black.opacity(0.45), in: Capsule())
        .padding(.horizontal, 24)
    }

    private func teamScore(_ country: Country, _ score: Int) -> some View {
        HStack(spacing: 8) {
            FlagView(country: country, height: 22)
            VStack(spacing: 2) {
                Text(country.name).font(.caption2.bold()).foregroundStyle(country.primaryColor)
                Text("\(score)").font(.system(size: 28, weight: .black, design: .rounded)).foregroundStyle(.white)
            }
        }
    }

    private var aiBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(model.aiActive ? .purple : .gray)
            Text(model.aiActive ? "Gemini AI" : "Rule AI")
                .font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: server.isPhoneConnected ? "iphone.gen3" : "iphone.slash")
                .foregroundStyle(server.isPhoneConnected ? .green : .gray)
            Text(server.isPhoneConnected ? "Connected" : "Keyboard (Space)")
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

// MARK: - カットイン

private struct CutInView: View {
    let cut: CutIn

    var body: some View {
        HStack(spacing: 0) {
            if !cut.fromLeft { Spacer() }
            content
            if cut.fromLeft { Spacer() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: cut.isManager ? .top : .bottom)
    }

    @ViewBuilder private var content: some View {
        if cut.isManager {
            // 監督：画像の「下」に文言を出す（重ならないように）。
            VStack(spacing: 10) {
                if let img = cut.image {
                    Image(nsImage: img)
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(height: 260)
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
                }
                banner
            }
            .padding(.horizontal, 40)
            .padding(.top, 80)   // スコアボードの下・画面上部に表示
        } else {
            // 選手：画像にタイトルを重ねる従来スタイル。
            ZStack(alignment: .bottom) {
                if let img = cut.image {
                    Image(nsImage: img)
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(height: 380)
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
                }
            }
            .overlay(alignment: cut.fromLeft ? .topTrailing : .topLeading) {
                banner.rotationEffect(.degrees(cut.fromLeft ? -6 : 6)).offset(y: 70)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
    }

    private var banner: some View {
        HStack(spacing: 6) {
            if cut.isManager { Text("🎯").font(.system(size: 28)) }
            Text(cut.title)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .background(cut.color.gradient, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 10)
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
                Text(success ? "SUCCESS!" : "MISS")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(success ? .green : .white.opacity(0.8))
                    .shadow(radius: 10)
            } else {
                gauge
                Text("Swing iPhone / Space")
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
            Text("MASH!").font(.headline.bold()).foregroundStyle(.orange)
                .scaleEffect(1 + CGFloat(chance.flash) * 1.5)
        }
    }
}
