import Testing
import SoccerShared

/// Mac ターゲットのスモークテスト。共有エンジンが Mac 側からも参照できることを確認。
struct SmokeTests {
    @Test func engineBootsWithFullRoster() {
        let engine = SoccerEngine()
        #expect(engine.players.count == Roster.total * 2)
    }
}
