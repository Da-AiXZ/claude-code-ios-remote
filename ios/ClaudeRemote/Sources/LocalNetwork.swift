import Foundation
import Darwin

enum LocalNetwork {
    static func parseIPv4(from string: String) -> String? {
        guard !string.isEmpty else { return nil }
        if string.hasPrefix("127.") { return nil }
        // 基础 IPv4 格式校验
        let parts = string.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ Int($0) != nil }) else { return nil }
        return string
    }

    static func formatAddress(ip: String?, port: UInt16) -> String {
        "\(ip ?? "(unknown)"):\(port)"
    }

    static func isLikelyLANAddress(_ ip: String) -> Bool {
        if ip.hasPrefix("127.") { return false }
        if ip.hasPrefix("192.168.") { return true }
        if ip.hasPrefix("10.") { return true }
        if ip.hasPrefix("172.") {
            let parts = ip.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
    }

    /// 遍历 getifaddrs，找到第一个非回环网卡上的 IPv4 地址。
    static func currentIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let cur = ptr {
            let iface = cur.pointee
            let addrFamily = iface.ifa_addr.pointee.sa_family
            if addrFamily == sa_family_t(AF_INET) {
                let name = String(cString: iface.ifa_name)
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(iface.ifa_addr,
                            socklen_t(iface.ifa_addr.pointee.sa_len),
                            &hostname,
                            socklen_t(hostname.count),
                            nil, 0, NI_NUMERICHOST)
                let ip = String(cString: hostname)
                if name.hasPrefix("en") || name.hasPrefix("pdp_ip") || name.hasPrefix("wl") {
                    if let parsed = parseIPv4(from: ip), isLikelyLANAddress(parsed) {
                        return parsed
                    }
                }
            }
            ptr = iface.ifa_next
        }
        return nil
    }
}
