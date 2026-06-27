import Testing
import simd
@testable import SoccerShared

struct KickDetectorTests {

    private let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    @Test func firesOnThresholdCross() {
        let det = KickDetector()
        // 閾値未満では発火しない
        #expect(det.processFrame(tNs: 0, rotationRate: SIMD3(1, 0, 0), attitude: identity, kind: .shoot) == nil)
        // 閾値超えで即発火
        let e = det.processFrame(tNs: 1_000_000, rotationRate: SIMD3(10, 0, 0), attitude: identity, kind: .shoot)
        #expect(e != nil)
        #expect(e?.kind == .shoot)
    }

    @Test func powerScalesWithOmega() {
        let det = KickDetector(config: .init(threshold: 3.5, maxOmega: 20))
        let weak = det.processFrame(tNs: 0, rotationRate: SIMD3(5, 0, 0), attitude: identity, kind: .shoot)
        #expect((weak?.power ?? 0) < 0.5)

        let det2 = KickDetector(config: .init(threshold: 3.5, maxOmega: 20))
        let strong = det2.processFrame(tNs: 0, rotationRate: SIMD3(40, 0, 0), attitude: identity, kind: .shoot)
        #expect((strong?.power ?? 0) == 1.0)  // clamp 上限
    }

    @Test func doesNotDoubleFireWithinSwing() {
        let det = KickDetector()
        let first = det.processFrame(tNs: 0, rotationRate: SIMD3(10, 0, 0), attitude: identity, kind: .shoot)
        #expect(first != nil)
        // charging 中の高速サンプルでは新規発火しない
        let dup = det.processFrame(tNs: 5_000_000, rotationRate: SIMD3(12, 0, 0), attitude: identity, kind: .shoot)
        #expect(dup == nil)
    }

    @Test func divingHeaderForcesHighLoft() {
        let det = KickDetector()
        let e = det.processFrame(tNs: 0, rotationRate: SIMD3(10, 0, 0), attitude: identity, kind: .divingHeader)
        #expect((e?.loft ?? 0) >= 0.7)
    }

    @Test func dribbleHasNoLoft() {
        let det = KickDetector()
        let e = det.processFrame(tNs: 0, rotationRate: SIMD3(10, 0, 0), attitude: identity, kind: .dribble)
        #expect(e?.loft == 0)
    }
}
