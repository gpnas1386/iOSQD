//
//  PortScanner.swift
//  TVRemote
//
//  TCP 端口探测：拿到电视 IP 后，判断它开放了哪些遥控端口，
//  据此决定该用哪种协议（Google TV / TCL / Roku / LG / ADB …）。
//

import Foundation
import Network

enum PortScanner {
    /// 已知端口 → 协议名
    static let knownPorts: [(port: UInt16, name: String)] = [
        (6466, "Google TV 遥控"),
        (6467, "Google TV 配对"),
        (6553, "TCL 遥控"),
        (8060, "Roku ECP"),
        (8009, "Chromecast"),
        (5555, "ADB 调试"),
        (9080, "DIAL 投屏"),
        (3000, "LG WebOS"),
        (3001, "LG WebOS"),
        (8002, "索尼 IRCC"),
        (36866, "三星遥控")
    ]

    static func probe(host: String,
                      timeout: TimeInterval = 1.2,
                      completion: @escaping ([UInt16]) -> Void) {
        let ports = knownPorts.map { $0.port }
        let group = DispatchGroup()
        let lock = NSLock()
        var opened: [UInt16] = []
        let queue = DispatchQueue(label: "tvremote.portscan", attributes: .concurrent)

        for port in ports {
            group.enter()
            probeOne(host: host, port: port, timeout: timeout, queue: queue) { ok in
                if ok {
                    lock.lock()
                    opened.append(port)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(opened.sorted())
        }
    }

    static func describe(_ ports: [UInt16]) -> String {
        guard !ports.isEmpty else { return "" }
        return ports.compactMap { p in
            knownPorts.first(where: { $0.port == p }).map { "\(p)(\($0.name))" }
        }.joined(separator: " ")
    }

    /// 根据开放端口推断协议
    static func inferProtocol(_ ports: [UInt16]) -> String {
        if ports.contains(6466) { return "Google TV" }
        if ports.contains(6553) { return "TCL" }
        if ports.contains(8060) { return "Roku" }
        if ports.contains(3000) || ports.contains(3001) { return "LG WebOS" }
        if ports.contains(5555) { return "Android ADB" }
        if ports.contains(8009) { return "Chromecast" }
        if ports.contains(9080) { return "DLNA" }
        return "未知"
    }

    private static func probeOne(host: String,
                                 port: UInt16,
                                 timeout: TimeInterval,
                                 queue: DispatchQueue,
                                 completion: @escaping (Bool) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion(false)
            return
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let lock = NSLock()
        var done = false

        func finish(_ ok: Bool) {
            lock.lock()
            if done {
                lock.unlock()
                return
            }
            done = true
            lock.unlock()
            conn.cancel()
            completion(ok)
        }

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(true)
            case .failed, .cancelled, .waiting:
                finish(false)
            default:
                break
            }
        }
        conn.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
    }
}
