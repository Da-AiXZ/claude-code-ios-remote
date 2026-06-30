import Foundation
import Network

enum TerminalServerError: Error {
    case invalidPort
    case alreadyRunning
}

enum ServerState: Equatable {
    case idle
    case starting
    case listening(address: String)
    case connected(address: String)
    case failed(String)
    case stopping
}

final class TerminalServer {
    let port: UInt16
    private let onMessage: (BridgeMessage) -> Void
    private let onStateChange: (ServerState) -> Void
    private(set) var state: ServerState = .idle {
        didSet { onStateChange(state) }
    }
    private var listener: NWListener?
    private var connection: NWConnection?
    private let parseContext = ParseContext()
    private let queue = DispatchQueue(label: "com.clauderemote.server")

    init(port: UInt16,
         onMessage: @escaping (BridgeMessage) -> Void,
         onStateChange: @escaping (ServerState) -> Void) throws {
        if port == 0 { throw TerminalServerError.invalidPort }
        self.port = port
        self.onMessage = onMessage
        self.onStateChange = onStateChange
    }

    func start() {
        guard listener == nil else { return }
        state = .starting
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] s in
                self?.handle(listenerState: s)
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.accept(conn)
            }
            listener.start(queue: queue)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        state = .stopping
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
        state = .idle
    }

    func send(_ msg: BridgeMessage) {
        guard let data = try? BridgeMessage.encode(msg) else { return }
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private func handle(listenerState: NWListener.State) {
        switch listenerState {
        case .ready:
            let ip = LocalNetwork.currentIPv4() ?? "127.0.0.1"
            state = .listening(address: LocalNetwork.formatAddress(ip: ip, port: port))
        case .failed(let err):
            state = .failed(err.localizedDescription)
        case .cancelled:
            state = .idle
        default:
            break
        }
    }

    private func accept(_ conn: NWConnection) {
        // 同一时间只接受一个连接。
        connection?.cancel()
        connection = conn
        conn.stateUpdateHandler = { [weak self] s in
            self?.handle(connectionState: s, conn: conn)
        }
        conn.start(queue: queue)
    }

    private func handle(connectionState: NWConnection.State, conn: NWConnection) {
        switch connectionState {
        case .ready:
            if let endpoint = conn.endpoint as? NWEndpoint.hostPort {
                let host = "\(endpoint.host)"
                let port = "\(endpoint.port)"
                state = .connected(address: "\(host):\(port)")
            } else {
                state = .connected(address: "unknown")
            }
            receiveLoop(conn)
        case .failed, .cancelled:
            let ip = LocalNetwork.currentIPv4() ?? "127.0.0.1"
            state = .listening(address: LocalNetwork.formatAddress(ip: ip, port: port))
            connection = nil
        default:
            break
        }
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receive { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data = data, !data.isEmpty {
                if let messages = try? BridgeMessage.decode(Buffer: data, ctx: self.parseContext) {
                    for msg in messages { self.onMessage(msg) }
                }
            }
            if isComplete || error != nil {
                let ip = LocalNetwork.currentIPv4() ?? "127.0.0.1"
                self.state = .listening(address: LocalNetwork.formatAddress(ip: ip, port: self.port))
                self.connection = nil
                return
            }
            self.receiveLoop(conn)
        }
    }
}
