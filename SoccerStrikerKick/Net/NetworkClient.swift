import Foundation
import Network
import OSLog
import SoccerShared

/// iPhone 側：Bonjour で Mac を発見し UDP NWConnection を張る。
/// 切断時は自動で browser を再起動して再接続する。
@MainActor
@Observable
final class NetworkClient {
    private let log = Logger(subsystem: "com.yabetatuki.soccerstriker.kick", category: "NetworkClient")
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var reconnectTask: Task<Void, Never>?

    var status: String = "Idle"
    var lastMessage: String = "-"
    var isConnected: Bool { connection?.state == .ready }

    /// Mac から GoalEvent を受け取ったとき。
    var onGoal: (@MainActor (GoalEvent) -> Void)?
    var onConnectionChanged: (@MainActor (Bool) -> Void)?

    func start() { startBrowser() }

    func stop() {
        reconnectTask?.cancel(); reconnectTask = nil
        connection?.cancel(); connection = nil
        browser?.cancel(); browser = nil
        status = "Stopped"
    }

    func resumeIfNeeded() {
        if connection == nil || connection?.state != .ready {
            restartBrowser()
        }
    }

    private func startBrowser() {
        guard browser == nil else { return }
        let params: NWParameters = .udp
        params.includePeerToPeer = true

        let b = NWBrowser(for: .bonjour(type: SSProtocol.serviceType, domain: nil), using: params)
        b.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                if case .failed = state { self.scheduleReconnect() }
                else { self.status = "Browser: \(state)" }
            }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            Task { @MainActor in
                if self.connection == nil, let first = results.first {
                    self.connect(to: first)
                }
            }
        }
        b.start(queue: .main)
        self.browser = b
        self.status = "Browsing"
    }

    private func restartBrowser() {
        browser?.cancel(); browser = nil
        connection?.cancel(); connection = nil
        startBrowser()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        status = "Reconnecting..."
        reconnectTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            restartBrowser()
        }
    }

    private func connect(to result: NWBrowser.Result) {
        connection?.cancel(); connection = nil
        let params: NWParameters = .udp
        params.includePeerToPeer = true

        let conn = NWConnection(to: result.endpoint, using: params)
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    self.status = "Connected"
                    self.sendHello()
                    self.onConnectionChanged?(true)
                case .failed, .cancelled:
                    self.status = "Disconnected"
                    self.connection = nil
                    self.onConnectionChanged?(false)
                    self.scheduleReconnect()
                default:
                    self.status = "\(state)"
                }
            }
        }
        conn.start(queue: .main)
        connection = conn
        receiveLoop()
    }

    func send(_ message: SSMessage) {
        guard let connection, connection.state == .ready else { return }
        do {
            let data = try message.encoded()
            connection.send(content: data, completion: .contentProcessed { [weak self] err in
                if let err { self?.log.error("send error: \(err.localizedDescription, privacy: .public)") }
            })
        } catch {
            log.error("encode error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sendHello() {
        send(.hello(HelloPayload(
            role: .controller,
            protoVersion: SSProtocol.version,
            tMono: DispatchTime.now().uptimeNanoseconds
        )))
    }

    private func receiveLoop() {
        connection?.receiveMessage { [weak self] data, _, _, err in
            guard let self else { return }
            Task { @MainActor in
                if err == nil, let data, !data.isEmpty {
                    if let msg = try? SSMessage.decode(data) { self.handle(msg) }
                }
                self.receiveLoop()
            }
        }
    }

    private func handle(_ msg: SSMessage) {
        switch msg {
        case .hello(let p):
            lastMessage = "hello from \(p.role.rawValue)"
        case .goal(let g):
            lastMessage = "\(g.outcome.rawValue) \(g.teamScore)-\(g.opponentScore)"
            onGoal?(g)
        default:
            break
        }
    }
}
