import Testing
import Foundation
@testable import ClaudeRemoteLib

@Suite struct TerminalSessionTests {
    @Test func 初始为idle() {
        let s = TerminalSession()
        #expect(s.phase == .idle)
    }

    @Test func start用配置端口启动服务器() throws {
        let s = TerminalSession(port: 19090)
        s.start()
        // .listening 带关联值（address: String），不能用 == .listening 比较，用 switch 模式匹配。
        let ok: Bool
        switch s.phase {
        case .starting, .listening: ok = true
        default: ok = false
        }
        #expect(ok)
        s.stop()
    }

    @Test func hello消息转为running() {
        let s = TerminalSession()
        s.start()
        s.handleMessage(BridgeMessage(type: .hello, version: "1.0.0", cols: 80, rows: 24))
        #expect(s.phase == .running)
        s.stop()
    }

    @Test func output消息推送给onOutput() throws {
        let s = TerminalSession()
        s.start()
        s.handleMessage(BridgeMessage(type: .hello, version: "1.0.0"))
        // 推送模式：output 字节通过 onOutput 回调直接送出，不再缓存到 receivedBytes。
        var captured = Data()
        s.onOutput = { data in captured.append(data) }
        let b64 = "hi".data(using: .utf8)!.base64EncodedString()
        s.handleMessage(BridgeMessage(type: .output, data: b64))
        #expect(captured == Data([0x68, 0x69]))
        s.stop()
    }

    @Test func exit消息转为exited() {
        let s = TerminalSession()
        s.start()
        s.handleMessage(BridgeMessage(type: .hello, version: "1.0.0"))
        s.handleMessage(BridgeMessage(type: .exit, code: 0, signal: nil))
        #expect(s.phase == .exited(code: 0))
        s.stop()
    }

    @Test func sendInput转发到服务器() throws {
        let s = TerminalSession()
        s.start()
        s.handleMessage(BridgeMessage(type: .hello, version: "1.0.0"))
        let captured = SentCapture()
        s.serverSender = { msg in captured.messages.append(msg) }
        let b64 = "x".data(using: .utf8)!.base64EncodedString()
        s.sendInput(Data([0x78]))
        #expect(captured.messages.count == 1)
        #expect(captured.messages[0].type == .input)
        #expect(captured.messages[0].data == b64)
        s.stop()
    }
}

private final class SentCapture {
    var messages: [BridgeMessage] = []
}
