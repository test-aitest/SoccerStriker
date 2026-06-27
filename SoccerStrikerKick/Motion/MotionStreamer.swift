import Foundation
import CoreMotion
import OSLog
import simd
import SoccerShared

/// `CMMotionManager` を 100Hz で回し、各サンプルを `KickDetector` に流して
/// 蹴り出しイベントを吐き出す薄いラッパ。
@MainActor
@Observable
final class MotionStreamer {
    private let log = Logger(subsystem: "com.yabetatuki.soccerstriker.kick", category: "MotionStreamer")
    private let manager = CMMotionManager()
    private let detector = KickDetector()

    var currentAngSpeed: Float = 0
    var lastKick: KickEvent?
    private(set) var isRunning = false
    var errorMessage: String?

    /// 蹴りイベント確定時に呼ばれる。
    var onKick: ((KickEvent) -> Void)?
    /// iPhone 側で選択中のアクション（shoot/pass/header/tackle）。
    var selectedKind: KickKind = .shoot

    func start() {
        guard manager.isDeviceMotionAvailable else {
            errorMessage = "Device motion is not available"
            return
        }
        guard !isRunning else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 100.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] dm, err in
            guard let self else { return }
            if let err { self.errorMessage = err.localizedDescription; return }
            guard let dm else { return }
            self.handle(motion: dm)
        }
        isRunning = true
        errorMessage = nil
    }

    func stop() {
        guard isRunning else { return }
        manager.stopDeviceMotionUpdates()
        isRunning = false
    }

    private func handle(motion dm: CMDeviceMotion) {
        let q = dm.attitude.quaternion
        let attitude = simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
        let rate = SIMD3<Float>(Float(dm.rotationRate.x), Float(dm.rotationRate.y), Float(dm.rotationRate.z))
        currentAngSpeed = simd_length(rate)

        let tNs = DispatchTime.now().uptimeNanoseconds
        if let kick = detector.processFrame(tNs: tNs, rotationRate: rate, attitude: attitude, kind: selectedKind) {
            lastKick = kick
            onKick?(kick)
            log.info("KICK kind=\(kick.kind.rawValue, privacy: .public) power=\(kick.power, privacy: .public) aim=\(kick.aim, privacy: .public)")
        }
    }
}
