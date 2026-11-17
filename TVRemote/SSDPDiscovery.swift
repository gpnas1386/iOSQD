//
//  SSDPDiscovery.swift
//  TVRemote
//
//  SSDP (UPnP) 设备发现。
//  几乎所有智能电视（TCL / Roku / Google TV / 索尼 / 三星 / LG）都会响应
//  M-SEARCH，因此这是最通用的「先把设备找出来」的手段。
//
//  发现到 IP 后，再去拉取设备描述文件拿友好名称，最后交给端口探测判断协议类型。
//

import Foundation
import Darwin

enum SSDPDiscovery {
    struct Found {
        let host: String
        let name: String
        let server: String
        let location: String
        let deviceType: String
    }

    static func scan(timeout: TimeInterval = 3.5,
                     log: @escaping (String) -> Void,
                     completion: @escaping ([Found]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let found = scanSync(timeout: timeout, log: log)
            DispatchQueue.main.async { completion(found) }
        }
    }

    // MARK: - 同步实现（后台队列）

    private static func scanSync(timeout: TimeInterval, log: @escaping (String) -> Void) -> [Found] {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            log("SSDP ✗ 创建 socket 失败 errno=\(errno)")
            return []
        }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var local = sockaddr_in()
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        local.sin_addr.s_addr = INADDR_ANY
        let bindResult = withUnsafePointer(to: &local) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindResult != 0 {
            log("SSDP ✗ bind 失败 errno=\(errno)")
        }

        var rcvTimeout = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &rcvTimeout, socklen_t(MemoryLayout<timeval>.size))

        let search = "M-SEARCH * HTTP/1.1\r\n"
            + "HOST: 239.255.255.250:1900\r\n"
            + "MAN: \"ssdp:discover\"\r\n"
            + "MX: 2\r\n"
            + "ST: ssdp:all\r\n\r\n"
        guard let payload = search.data(using: .utf8) else { return [] }

        // 目标：UPnP 组播 + 全局广播 + 各网段定向广播
        var targets = ["239.255.255.250", "255.255.255.255"]
        for t in NetworkInfo.broadcastTargets() where !targets.contains(t) {
            targets.append(t)
        }
        log("SSDP → 发送 M-SEARCH 到 \(targets.joined(separator: ", "))")

        var responses: [String: [String: String]] = [:]
        var buf = [UInt8](repeating: 0, count: 8192)
        let deadline = Date().addingTimeInterval(timeout)
        var lastSend = Date.distantPast

        while Date() < deadline {
            if Date().timeIntervalSince(lastSend) > 1.2 {
                for t in targets {
                    sendDatagram(fd: fd, payload: payload, ip: t, port: 1900)
                }
                lastSend = Date()
            }

            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buf, buf.count, 0, $0, &fromLen)
                }
            }
            guard n > 0 else { continue }
            guard let text = String(bytes: buf[0..<n], encoding: .utf8),
                  text.hasPrefix("HTTP/1.") else { continue }

            let headers = parseHeaders(text)
            let host = headers["location"].flatMap(hostFromURL) ?? ipString(from: from)
            guard let ip = host, !ip.isEmpty else { continue }

            if responses[ip] == nil {
                responses[ip] = headers
            } else if headers["location"] != nil && responses[ip]?["location"] == nil {
                responses[ip] = headers
            }
        }

        log("SSDP ← 共 \(responses.count) 台设备响应")

        // 并发拉取设备描述补名称
        var results: [Found] = []
        let lock = NSLock()
        let group = DispatchGroup()

        for (ip, headers) in responses {
            let server = headers["server"] ?? ""
            guard let location = headers["location"], let url = URL(string: location) else {
                lock.lock()
                results.append(Found(host: ip, name: "设备 \(ip)", server: server, location: "", deviceType: ""))
                lock.unlock()
                continue
            }
            group.enter()
            fetchDescription(url: url) { name, deviceType in
                lock.lock()
                results.append(Found(host: ip,
                                     name: name ?? "设备 \(ip)",
                                     server: server,
                                     location: location,
                                     deviceType: deviceType ?? ""))
                lock.unlock()
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 3.0)

        // 过滤掉路由器 / NAS 等非显示设备
        let filtered = results.filter { r in
            let type = r.deviceType.lowercased()
            let name = r.name.lowercased()
            let server = r.server.lowercased()
            if type.contains("mediarenderer") || type.contains("mediaserver") { return true }
            if server.contains("tv") || server.contains("tcl") || server.contains("roku")
                || server.contains("android") || server.contains("webos") || server.contains("tizen") {
                return true
            }
            if name.contains("tv") || name.contains("电视") || name.contains("雷鸟") { return true }
            // 拿不到描述信息的也保留（可能是电视），交由后续端口探测判断
            return type.isEmpty
        }
        log("SSDP 判定为电视/显示设备 \(filtered.count) 台")
        return filtered
    }

    // MARK: - 工具

    private static func sendDatagram(fd: Int32, payload: Data, ip: String, port: UInt16) {
        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = port.bigEndian
        dest.sin_addr.s_addr = inet_addr(ip)
        guard dest.sin_addr.s_addr != INADDR_NONE else { return }
        _ = payload.withUnsafeBytes { rawBuf in
            withUnsafePointer(to: &dest) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, rawBuf.baseAddress, rawBuf.count, 0, $0,
                           socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private static func parseHeaders(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: "\r\n") {
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<idx].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { result[key] = value }
        }
        return result
    }

    private static func hostFromURL(_ s: String) -> String? {
        URL(string: s)?.host
    }

    private static func ipString(from addr: sockaddr_in) -> String? {
        var a = addr.sin_addr
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &a, &buf, socklen_t(buf.count)) != nil else { return nil }
        return String(cString: buf)
    }

    private static func fetchDescription(url: URL,
                                         completion: @escaping (String?, String?) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data, let xml = String(data: data, encoding: .utf8) else {
                completion(nil, nil)
                return
            }
            let name = firstMatch(xml, pattern: "<friendlyName>(.*?)</friendlyName>")
            let type = firstMatch(xml, pattern: "<deviceType>(.*?)</deviceType>")
            completion(name?.trimmingCharacters(in: .whitespacesAndNewlines),
                       type?.trimmingCharacters(in: .whitespacesAndNewlines))
        }.resume()
    }

    private static func firstMatch(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, options: [], range: range),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
