import SwiftUI
import UIKit
import SoccerShared

@main
struct SoccerStrikerKickApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var client = NetworkClient()
    @State private var motion = MotionStreamer()
    @State private var haptics = HapticsPlayer()

    var body: some Scene {
        WindowGroup {
            KickView(client: client, motion: motion)
                .onAppear { startAll() }
                .onDisappear {
                    motion.stop(); client.stop(); haptics.stop()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                haptics.restart(); motion.start(); client.resumeIfNeeded()
            case .background:
                motion.stop()
            default: break
            }
        }
    }

    private func startAll() {
        client.start()
        motion.start()
        haptics.start()

        // 蹴り → ネット送信 + 即時ハプティクス
        motion.onKick = { [weak client, weak haptics] kick in
            client?.send(.kick(kick))
            haptics?.playKick(power: kick.power)
        }
        // Mac からの得点フィードバック
        client.onGoal = { [weak haptics] goal in
            haptics?.play(goal: goal)
        }
        client.onConnectionChanged = { [weak haptics] connected in
            if connected { haptics?.restart() }
        }
        // 蹴っている最中に画面が消えないように
        UIApplication.shared.isIdleTimerDisabled = true
    }
}
