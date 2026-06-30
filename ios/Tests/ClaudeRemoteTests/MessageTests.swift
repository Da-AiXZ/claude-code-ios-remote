import Testing
import Foundation
@testable import ClaudeRemoteLib

@Suite struct MessageTests {
    @Test func 编码hello消息() throws {
        let msg = BridgeMessage(type: .hello, version: "1.0.0", cols: 80, rows: 24)
        let data = try BridgeMessage.encode(msg)
        let s = String(data: data, encoding: .utf8)
        #expect(s == #"{"type":"hello","version":"1.0.0","cols":80,"rows":24}"# + "\n")
    }

    @Test func 编码output消息() throws {
        let bytes = "hi".data(using: .utf8)!.base64EncodedString()
        let msg = BridgeMessage(type: .output, data: bytes)
        let data = try BridgeMessage.encode(msg)
        let s = String(data: data, encoding: .utf8)
        #expect(s == #"{"type":"output","data":"aGk="}"# + "\n")
    }

    @Test func 解码input消息() throws {
        let line = #"{"type":"input","data":"aGk="}"# + "\n"
        let msgs = try BridgeMessage.decode(Buffer: line.data(using: .utf8)!, ctx: ParseContext())
        #expect(msgs.count == 1)
        #expect(msgs[0].type == .input)
        #expect(msgs[0].data == "aGk=")
    }

    @Test func 一个buffer解码多条消息() throws {
        let chunk = #"{"type":"output","data":"aGk="}{"type":"exit","code":0}"# + "\n"
        let msgs = try BridgeMessage.decode(Buffer: chunk.data(using: .utf8)!, ctx: ParseContext())
        #expect(msgs.count == 2)
        #expect(msgs[0].type == .output)
        #expect(msgs[1].type == .exit)
        #expect(msgs[1].code == 0)
    }

    @Test func 解码缓存半行() throws {
        let ctx = ParseContext()
        let part1 = #"{"type":"output","data":"aGk="}"#.data(using: .utf8)!
        let part2 = "\n".data(using: .utf8)!
        #expect(try BridgeMessage.decode(Buffer: part1, ctx: ctx).isEmpty)
        #expect(try BridgeMessage.decode(Buffer: part2, ctx: ctx).count == 1)
    }

    @Test func 解码拒绝未知类型() {
        #expect(throws: DecodingError.self) {
            _ = try BridgeMessage.decode(Buffer: #"{"type":"bogus"}"#.data(using: .utf8)!, ctx: ParseContext())
        }
    }
}
