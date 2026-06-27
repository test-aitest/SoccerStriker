import Foundation
import simd

/// iPhone の 100Hz モーションストリームを読み、蹴り出しの瞬間に
/// `KickEvent` を 1 発だけ発火する状態機械。
///
/// 設計は HomeRunDerby の SwingDetector を踏襲：
/// **idle → charging 遷移（閾値クロス）の瞬間に即発火**することで、
/// 蹴り出し開始から Mac 側のボール反応までの遅延を最小化する。
///
/// 発火時に端末姿勢から以下を導出して `KickEvent` に載せる：
///   - power : 角速度ピークを正規化したシュート強度
///   - aim   : 端末ヨーから求める左右の狙い (-1…1)
///   - loft  : 端末ピッチ（+選択キックの種類）から求める浮かせ具合 (0…1)
///
/// `CMMotionManager` に依存しない pure Swift なので UnitTest で検証できる。
public final class KickDetector: @unchecked Sendable {

    public struct Config: Sendable {
        public var threshold: Float          // 発火する角速度 (rad/s)
        public var maxOmega: Float           // power=1.0 に対応する角速度 (rad/s)
        public var dropRatio: Float          // charging→cooldown の減衰率 (0..1)
        public var cooldownDuration: Double  // 秒

        public init(
            threshold: Float = 3.5,
            maxOmega: Float = 22.0,
            dropRatio: Float = 0.8,
            cooldownDuration: Double = 0.30
        ) {
            self.threshold = threshold
            self.maxOmega = maxOmega
            self.dropRatio = dropRatio
            self.cooldownDuration = cooldownDuration
        }
    }

    public enum State: Sendable, Equatable {
        case idle
        case charging
        case cooldown
    }

    public private(set) var state: State = .idle
    public let config: Config

    private var seqCounter: UInt32 = 0
    private var peakOmega: Float = 0
    private var cooldownUntilTNs: UInt64 = 0

    public init(config: Config = Config()) {
        self.config = config
    }

    public func reset() {
        state = .idle
        peakOmega = 0
        cooldownUntilTNs = 0
    }

    /// 1 フレームのモーションサンプルを処理し、蹴り出しの瞬間にだけ
    /// `KickEvent` を返す。`kind` は iPhone 側で選択中のアクション。
    public func processFrame(
        tNs: UInt64,
        rotationRate: SIMD3<Float>,
        attitude: simd_quatf,
        kind: KickKind
    ) -> KickEvent? {
        let omega = simd_length(rotationRate)

        switch state {
        case .cooldown:
            if tNs >= cooldownUntilTNs { state = .idle }
            return nil

        case .idle:
            if omega >= config.threshold {
                state = .charging
                peakOmega = omega
                return emit(tNs: tNs, omega: omega, attitude: attitude, kind: kind)
            }
            return nil

        case .charging:
            if omega > peakOmega { peakOmega = omega }
            if omega < peakOmega * config.dropRatio {
                state = .cooldown
                cooldownUntilTNs = tNs + UInt64(config.cooldownDuration * 1_000_000_000)
            }
            return nil
        }
    }

    private func emit(
        tNs: UInt64,
        omega: Float,
        attitude: simd_quatf,
        kind: KickKind
    ) -> KickEvent {
        seqCounter += 1
        let power = simd_clamp(omega / config.maxOmega, 0, 1)
        let (yaw, pitch) = Self.yawPitch(from: attitude)

        // ヨー（左右の向き）→ 狙い。±45° で端まで振り切る。
        let aim = simd_clamp(yaw / (Float.pi / 4), -1, 1)

        // ピッチ（前後の傾き）→ 浮かせ具合。上向きほどロフト大。
        // ダイビングヘッドは常に高ロフト、ドリブルは常にグラウンダー。
        let pitchLoft = simd_clamp((pitch + 0.2) / (Float.pi / 3), 0, 1)
        let loft: Float
        switch kind {
        case .divingHeader: loft = max(0.7, pitchLoft)
        case .dribble:      loft = 0
        case .shoot:        loft = pitchLoft
        }

        return KickEvent(
            seq: seqCounter,
            tMono: tNs,
            kind: kind,
            power: power,
            aim: aim,
            loft: loft
        )
    }

    /// クォータニオンからヨー(z軸まわり)とピッチ(y軸まわり)を抜き出す簡易版。
    /// `.xArbitraryZVertical` 基準の姿勢を想定。
    static func yawPitch(from q: simd_quatf) -> (yaw: Float, pitch: Float) {
        let w = q.real, x = q.imag.x, y = q.imag.y, z = q.imag.z
        // yaw (z軸)
        let siny = 2 * (w * z + x * y)
        let cosy = 1 - 2 * (y * y + z * z)
        let yaw = atan2(siny, cosy)
        // pitch (y軸)
        let sinp = 2 * (w * y - z * x)
        let pitch = abs(sinp) >= 1 ? Float(copysign(Double.pi / 2, Double(sinp))) : asin(sinp)
        return (yaw, pitch)
    }
}
