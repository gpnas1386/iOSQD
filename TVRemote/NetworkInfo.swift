//
//  NetworkInfo.swift
//  TVRemote
//
//  读取本机各网络接口的 IPv4 地址、子网掩码、广播地址。
//  用于：1) 首屏显示手机 Wi-Fi IP（用户可核对是否真在同一网段）
//        2) 计算正确的定向广播地址（不要再用硬编码的 192.168.255.255）
//

import Foundation
import Darwin

enum NetworkInfo {
    struct Interface {
        let name: String        // en0 / pdp_ip0 …
        let address: String     // 192.168.1.23
        let netmask: String     // 255.255.255.0
        let broadcast: String?  // 192.168.1.255
    }

    /// 当前所有已启用的 IPv4 网络接口（不含回环）
    static func localInterfaces() -> [Interface] {
        var result: [Interface] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return [] }
        defer { freeifaddrs(ifaddrPtr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            let ifa = ptr.pointee
            cursor = ifa.ifa_next

            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(ifa.ifa_flags)
            // 跳过未启用 / 回环
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }

            let name = String(cString: ifa.ifa_name)
            let address = ipString(sa)
            guard !address.isEmpty else { continue }

            var mask = ""
            if let nm = ifa.ifa_netmask {
                mask = ipString(nm)
            }
            var broadcast: String?
            if let dst = ifa.ifa_dstaddr, (flags & IFF_BROADCAST) != 0 {
                let b = ipString(dst)
                if !b.isEmpty && b != address { broadcast = b }
            }
            result.append(Interface(name: name, address: address, netmask: mask, broadcast: broadcast))
        }
        return result
    }

    /// Wi-Fi（en0）的地址，没有则返回第一个非蜂窝接口
    static func wifiInterface() -> Interface? {
        let all = localInterfaces()
        if let en0 = all.first(where: { $0.name == "en0" }) { return en0 }
        return all.first(where: { !$0.name.hasPrefix("pdp_ip") })
    }

    /// 是否正在使用蜂窝网络（用于提示用户连 Wi-Fi）
    static func isCellularOnly() -> Bool {
        let all = localInterfaces()
        let hasWiFi = all.contains { $0.name == "en0" }
        let hasCell = all.contains { $0.name.hasPrefix("pdp_ip") }
        return hasCell && !hasWiFi
    }

    /// 所有需要发送广播的地址：全局广播 + 各接口定向广播 + 组播地址
    static func broadcastTargets() -> [String] {
        var targets: [String] = ["255.255.255.255"]
        for itf in localInterfaces() {
            if let b = itf.broadcast, !targets.contains(b) {
                targets.append(b)
            }
            // 有些系统不给 ifa_dstaddr，用 /24 兜底推算
            if itf.broadcast == nil, let guess = guessBroadcast24(address: itf.address) {
                if !targets.contains(guess) { targets.append(guess) }
            }
        }
        return targets
    }

    private static func guessBroadcast24(address: String) -> String? {
        let parts = address.components(separatedBy: ".")
        guard parts.count == 4 else { return nil }
        return "\(parts[0]).\(parts[1]).\(parts[2]).255"
    }

    private static func ipString(_ sa: UnsafeMutablePointer<sockaddr>) -> String {
        var sin = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let ok = withUnsafePointer(to: &sin.sin_addr) { addrPtr in
            inet_ntop(AF_INET, addrPtr, &buf, socklen_t(buf.count))
        }
        guard ok != nil else { return "" }
        return String(cString: buf)
    }
}
