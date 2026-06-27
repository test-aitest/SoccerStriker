import Foundation
import Network
import OSLog
import SoccerShared

/// 単一の iPhone との双方向 UDP メッセージング。NWListener から受け取った
/// NWConnection を保持し、JSON シリアライズされた SSMessage を送受信する。
@MainActor
final class PeerSession {
    private let log = Logger(subsystem: "com.yabetatuki.soccerstriker.mac", category: "PeerSession")
    private let connection: NWConnection
    private var onMessage: ((SSMessage) -> Void)?
    private var onStateChange: ((NWConnection.State) -> Void)?

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start(
        onMessage: @escaping (SSMessage) -> Void,
        onStateChange: @escaping (NWConnection.State) -> Void
    ) {
        self.onMessage = onMessage
        self.onStateChange = onStateChange

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                self.log.info("connection state: \(String(describing: state), privacy: .public)")
                self.onStateChange?(state)
                if case .ready = state {
                    self.sendHello()
                }
            }
        }
        connection.start(queue: .main)
        receiveLoop()
    }

    func cancel() {
        connection.cancel()
    }

    func send(_ message: SSMessage) {
        do {
            let data = try message.encoded()
            connection.send(content: data, completion: .contentProcessed { [weak self] err in
                if let err {
                    self?.log.error("send error: \(err.localizedDescription, privacy: .public)")
                }
            })
        } catch {
            log.error("encode error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sendHello() {
        let hello = HelloPayload(
            role: .mac,
            protoVersion: SSProtocol.version,
            tMono: DispatchTime.now().uptimeNanoseconds
        )
        send(.hello(hello))
        log.info("sent hello from mac")
    }

    private func receiveLoop() {
        connection.receiveMessage { [weak self] data, _, _, err in
            guard let self else { return }
            Task { @MainActor in
                if let err {
                    self.log.error("receive error: \(err.localizedDescription, privacy: .public)")
                    return
                }
                if let data, !data.isEmpty {
                    do {
                        let msg = try SSMessage.decode(data)
                        self.onMessage?(msg)
                    } catch {
                        self.log.error("decode error: \(error.localizedDescription, privacy: .public)")
                    }
                }
                self.receiveLoop()
            }
        }
    }
}
