import Foundation
import Combine

enum SessionPhase: Equatable {
    case idle
    case starting
    case listening(address: String)
    case running
    case exited(code: Int)
    case failed(String)

    static func == (lhs: SessionPhase, rhs: SessionPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.starting, .starting), (.running, .running): return true
        case (.listening(let a), .listening(let b)): return a == b
        case (.exited(let a), .exited(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

final class TerminalSession: ObservableObject {
    @Published var phase: SessionPhase = .idle
    @Published var receivedBytes: Data = Data()
    @Published var statusText: String = "Idle"
    let port: UInt16
    var serverSender: ((BridgeMessage) -> Void)?

    private var server: TerminalServer?

    init(port: UInt16 = 8080) {
        self.port = port
        start()
    }

    func start() {
        guard server == nil else { return }
        phase = .starting
        do {
            let server = try TerminalServer(
                port: port,
                onMessage: { [weak self] msg in
                    DispatchQueue.main.async { self?.handleMessage(msg) }
                },
                onStateChange: { [weak self] state in
                    DispatchQueue.main.async { self?.handle(serverState: state) }
                }
            )
            self.server = server
            self.serverSender = { [weak server] msg in server?.send(msg) }
            server.start()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func stop() {
        server?.stop()
        server = nil
        phase = .idle
    }

    func handleMessage(_ msg: BridgeMessage) {
        switch msg.type {
        case .hello:
            phase = .running
        case .output:
            if let b64 = msg.data, let bytes = Data(base64Encoded: b64) {
                receivedBytes.append(bytes)
            }
        case .exit:
            let code = msg.code ?? 0
            phase = .exited(code: code)
        case .error:
            if let m = msg.message { phase = .failed(m) }
        default:
            break
        }
    }

    func sendInput(_ data: Data) {
        let msg = BridgeMessage(type: .input, data: data.base64EncodedString())
        serverSender?(msg)
    }

    func sendResize(cols: Int, rows: Int) {
        let msg = BridgeMessage(type: .resize, cols: cols, rows: rows)
        serverSender?(msg)
    }

    private func handle(serverState: ServerState) {
        switch serverState {
        case .idle:
            if phase != .running { phase = .idle }
        case .starting:
            phase = .starting
        case .listening(let addr):
            if phase != .running { phase = .listening(address: addr) }
            statusText = "Listening on \(addr)"
        case .connected:
            statusText = "Bridge connected"
        case .failed(let msg):
            phase = .failed(msg)
        case .stopping:
            break
        }
    }
}
