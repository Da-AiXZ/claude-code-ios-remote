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
