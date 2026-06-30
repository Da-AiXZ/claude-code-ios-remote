import Foundation

enum MessageType: String, Codable {
    case hello, output, exit, input, resize, error
}

struct BridgeMessage: Codable {
    let type: MessageType
    var version: String?
    var cols: Int?
    var rows: Int?
    var data: String?
    var code: Int?
    var signal: String?
    var message: String?
}

final class ParseContext {
    var buffer: String = ""
}

extension BridgeMessage {
    static func encode(_ msg: BridgeMessage) throws -> Data {
        let encoder = JSONEncoder()
        // 用 .sortedKeys 保证字段顺序稳定（字母序）。
        // Foundation 的 JSONEncoder 内部用 Dictionary 存储，不加 .sortedKeys 时遍历顺序不确定，
        // 会导致同一消息每次编码的字节序列不同，无法稳定断言和做字节级比对。
        // JSON 语义上字段无序，bridge.js 端 JSON.parse 也不依赖顺序，所以字母序不影响功能。
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        var data = try encoder.encode(msg)
        data.append(0x0A) // \n
        return data
    }

    static func decode(Buffer chunk: Data, ctx: ParseContext) throws -> [BridgeMessage] {
        guard let text = String(data: chunk, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "non-utf8"))
        }
        ctx.buffer += text
        var messages: [BridgeMessage] = []
        let decoder = JSONDecoder()
        while let nlIdx = ctx.buffer.firstIndex(of: "\n") {
            let line = String(ctx.buffer[ctx.buffer.startIndex..<nlIdx])
            ctx.buffer.removeSubrange(ctx.buffer.startIndex...nlIdx)
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let lineData = line.data(using: .utf8) else { continue }
            messages.append(try decoder.decode(BridgeMessage.self, from: lineData))
        }
        return messages
    }
}
