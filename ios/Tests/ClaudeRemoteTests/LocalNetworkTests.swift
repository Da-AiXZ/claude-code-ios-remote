import Testing
import Foundation
@testable import ClaudeRemoteLib

@Suite struct LocalNetworkTests {
    @Test func 解析合法IPv4() {
        let ip = LocalNetwork.parseIPv4(from: "192.168.1.42")
        #expect(ip == "192.168.1.42")
    }

    @Test func 回环地址返回nil() {
        let ip = LocalNetwork.parseIPv4(from: "127.0.0.1")
        #expect(ip == nil)
    }

    @Test func 空字符串返回nil() {
        let ip = LocalNetwork.parseIPv4(from: "")
        #expect(ip == nil)
    }

    @Test func 拼接IP和端口() {
        let addr = LocalNetwork.formatAddress(ip: "192.168.1.42", port: 8080)
        #expect(addr == "192.168.1.42:8080")
    }

    @Test func ip为nil时显示占位() {
        let addr = LocalNetwork.formatAddress(ip: nil, port: 8080)
        #expect(addr == "(unknown):8080")
    }

    @Test func 私网地址识别为局域网() {
        #expect(LocalNetwork.isLikelyLANAddress("192.168.0.5"))
        #expect(LocalNetwork.isLikelyLANAddress("10.0.0.5"))
        #expect(LocalNetwork.isLikelyLANAddress("172.16.0.5"))
    }

    @Test func 公网地址不识别为局域网() {
        #expect(!LocalNetwork.isLikelyLANAddress("8.8.8.8"))
        #expect(!LocalNetwork.isLikelyLANAddress("127.0.0.1"))
    }
}
