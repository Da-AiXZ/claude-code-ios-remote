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
