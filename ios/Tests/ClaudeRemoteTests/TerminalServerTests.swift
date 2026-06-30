import Testing
import Foundation
import Network
@testable import ClaudeRemoteLib

@Suite struct TerminalServerTests {
    @Test func 端口0拒绝() {
        #expect(throws: TerminalServerError.invalidPort.self) {
            _ = try TerminalServer(port: 0, onMessage: { _ in }, onStateChange: { _ in })
        }
    }

    @Test func 合法端口可创建() throws {
        // 只做参数校验，不在单元测试里真正启动 listener。
        let s = try TerminalServer(port: 18080, onMessage: { _ in }, onStateChange: { _ in })
        #expect(s.port == 18080)
    }

    @Test func 启动前状态是idle() throws {
        let s = try TerminalServer(port: 18081, onMessage: { _ in }, onStateChange: { _ in })
        #expect(s.state == .idle)
    }

    @Test func stop后转为idle或stopping() throws {
        let s = try TerminalServer(port: 18082, onMessage: { _ in }, onStateChange: { _ in })
        s.start()
        s.stop()
        // stop 后状态应最终为 idle（同步 cancel）。
        #expect(s.state == .idle || s.state == .stopping)
    }
}
