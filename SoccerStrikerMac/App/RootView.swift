import SwiftUI

/// ルート。タイトル ↔ 試合。
struct RootView: View {
    @Bindable var server: NetworkServer
    @State private var route: Route = .title
    @State private var titleBGM = MusicPlayer(resource: "title", volume: 0.55)

    enum Route { case title, match }

    var body: some View {
        ZStack {
            switch route {
            case .title:
                TitleView(onStart: { route = .match })
            case .match:
                MatchView(server: server, onExit: { route = .title })
            }
        }
        .frame(minWidth: 960, minHeight: 600)
        .animation(.easeInOut(duration: 0.25), value: route)
        .onAppear { titleBGM.play() }
        .onChange(of: route) { _, newRoute in
            // タイトルでは BGM、試合中はスタジアム環境音に切替。
            if newRoute == .title { titleBGM.play() } else { titleBGM.stop() }
        }
    }
}

private struct TitleView: View {
    let onStart: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.12, blue: 0.07), .black],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Text("SOCCER STRIKER")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("4 vs 4 ・ iPhone を振って蹴る")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))

                Button(action: onStart) {
                    Text("キックオフ")
                        .font(.title2.bold())
                        .padding(.horizontal, 48).padding(.vertical, 16)
                        .background(Color.green, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)

                Text("両チームは AI が自動でプレイします。\nシュートチャンスとピンチでゲージが出るので iPhone を振る（または Space）で介入！")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 12)
            }
        }
    }
}
