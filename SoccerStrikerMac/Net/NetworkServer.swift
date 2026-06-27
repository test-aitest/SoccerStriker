import Foundation
import Network
import OSLog
import SoccerShared

/// Bonjour (_socstrk._udp) を広告して iPhone から発見させ、接続を PeerSession で
/// ラップする。最新 1 台の接続のみ保持する。
@MainActor
@Observable
final class NetworkServer {
    private let log = Logger(subsystem: "com.yabetatuki.soccerstriker.mac", category: "NetworkServer")
    private var listener: NWListener?
    private(set) var session: PeerSession?

    var status: String = "Not started"
    var isPhoneConnected: Bool = false
    var kickReceivedCount: Int = 0
    var lastKickReceivedAt: Date?

    /// KickEvent 受信時に呼ばれる。GameModel.kick() に接続する。
    var onKick: (@MainActor (KickEvent) -> Void)?
    /// 姿勢ストリーム（HUD のリアルタイム狙い表示用、任意）。
    var onAttitude: (@MainActor (AttitudeFrame) -> Void)?
    /// iPhone の接続/切断を通知。
    var onConnectionChanged: (@MainActor (Bool) -> Void)?

    func start() {
        guard listener == nil else { return }
        do {
            let params: NWParameters = .udp
            params.allowLocalEndpointReuse = true
            // AWDL を有効化し、共通 Wi-Fi が無くても iPhone と直結できるようにする。
            params.includePeerToPeer = true

            let listener = try NWListener(using: params)
            listener.service = NWListener.Service(
                name: "SoccerStrikerMac",
                type: SSProtocol.serviceType
            )
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                Task { @MainActor in
                    self.log.info("listener state: \(String(describing: state), privacy: .public)")
                    self.status = "Listener: \(state)"
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                guard let self else { return }
                Task { @MainActor in
                    self.session?.cancel()
                    let name = Self.endpointName(conn.endpoint)
                    self.log.info("new connection from \(name, privacy: .public)")
                    self.status = "Connected: \(name)"
                    self.isPhoneConnected = true
                    self.onConnectionChanged?(true)
                    let session = PeerSession(connection: conn)
                    self.session = session
                    session.start(
                        onMessage: { [weak self] msg in self?.handle(msg) },
                        onStateChange: { [weak self] state in
                            if case .failed = state { self?.markDisconnected() }
                            if case .cancelled = state { self?.markDisconnected() }
                        }
                    )
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            self.status = "Listening"
            log.info("listener advertising \(SSProtocol.serviceType, privacy: .public)")
        } catch {
            log.error("failed to start listener: \(error.localizedDescription, privacy: .public)")
            status = "Error: \(error.localizedDescription)"
        }
    }

    func stop() {
        session?.cancel()
        session = nil
        listener?.cancel()
        listener = nil
        status = "Stopped"
    }

    /// Mac → iPhone のフィードバック（得点/振動）。
    func sendGoal(_ event: GoalEvent) {
        session?.send(.goal(event))
    }

    private func markDisconnected() {
        status = "Disconnected"
        isPhoneConnected = false
        onConnectionChanged?(false)
    }

    private static func endpointName(_ ep: NWEndpoint) -> String {
        switch ep {
        case .hostPort(let host, _): return "\(host)"
        case .service(let name, _, _, _): return name
        default: return "\(ep)"
        }
    }

    private func handle(_ msg: SSMessage) {
        switch msg {
        case .hello:
            break
        case .attitude(let f):
            onAttitude?(f)
        case .kick(let e):
            kickReceivedCount += 1
            lastKickReceivedAt = Date()
            log.info("RX kick seq=\(e.seq, privacy: .public) kind=\(e.kind.rawValue, privacy: .public) power=\(e.power, privacy: .public)")
            onKick?(e)
        case .goal:
            // Mac は goal の送信側。受信は想定外。
            break
        }
    }
}
