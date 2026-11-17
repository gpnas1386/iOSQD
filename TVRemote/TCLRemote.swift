//
//  TCLRemote.swift
//  TVRemote
//
//  TCL / 雷鸟 电视局域网遥控协议客户端
//  协议参考开源项目 jarvis2f/tcl-remote (MIT)：
//    - 设备发现：UDP 6537 广播
//    - 控制连接：TCP 6553，帧格式为 4 字节大端长度 + payload
//    - 握手包：159>><client_name>>1>><client_id>>1
//    - 按键包：149>><key_code>
//    - 若电视握手响应 algorithmType == 1，则后续 payload 使用 AES-128-CBC 加密
//

import Foundation
import Network
import Darwin

final class TCLRemote {
    enum Key: Int {
        case power = 20
        case up = 11
        case down = 12
        case left = 13
        case right = 14
        case ok = 15
        case back = 16
        case menu = 18
        case home = 19
        case volUp = 21
        case volDown = 22
        case mute = 23
        case chUp = 27
        case chDown = 28
    }

    struct Device {
        let name: String
        let host: String
        var id: String { host }
    }

    private let clientName: String
    private let clientID: String
    private var connection: NWConnection?
    private var recvBuffer = Data()
    private var useAES = false
    private let queue = DispatchQueue(label: "tvremote.tcl")

    /// 连接意外断开时回调（主动 disconnect 不触发）
    var onDisconnect: (() -> Void)?
    private var hasConnected = false
    private var closedIntentionally = false

    init(clientName: String = "TV Remote") {
        self.clientName = clientName
        self.clientID = String(UUID().uuidString.prefix(16))
    }

    // MARK: - 设备发现

    static func discover(timeout: TimeInterval = 4,
                         log: @escaping (String) -> Void,
                         completion: @escaping ([Device]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = discoverSync(timeout: timeout, log: log)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func discoverSync(timeout: TimeInterval, log: @escaping (String) -> Void) -> [Device] {
        var found: [String: Device] = [:]

        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            log("TCL ✗ 创建 socket 失败 errno=\(errno)")
            return []
        }
        defer { close(fd) }

        var broadcast: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &broadcast, socklen_t(MemoryLayout<Int32>.size))

        // 绑定到临时端口即可：电视的响应会回到数据包源端口
        var bindAddr = sockaddr_in()
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port = 0
        bindAddr.sin_addr.s_addr = INADDR_ANY
        let bindResult = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindResult != 0 {
            log("TCL ✗ bind 失败 errno=\(errno)")
        }

        var tv = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        let myName = "TV Remote"
        let uuid = UUID().uuidString
        let msg = "1:\(ts):\(myName):PHONE:1:\(myName):\(uuid):0:0\0"
        guard let pkt = msg.data(using: .utf8) else { return [] }

        // 正确计算各网段广播地址，取代硬编码的 192.168.255.255
        let targets = NetworkInfo.broadcastTargets()
        log("TCL → 广播到 \(targets.joined(separator: ", ")) 端口 6537")

        func sendBroadcast(to ip: String) {
            var dest = sockaddr_in()
            dest.sin_family = sa_family_t(AF_INET)
            dest.sin_port = UInt16(6537).bigEndian
            dest.sin_addr.s_addr = inet_addr(ip)
            guard dest.sin_addr.s_addr != INADDR_NONE else { return }
            let sent = pkt.withUnsafeBytes { buf -> Int in
                withUnsafePointer(to: &dest) { p in
                    p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                        sendto(fd, buf.baseAddress, buf.count, 0, sp,
                               socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if sent < 0 {
                log("TCL ✗ 发送到 \(ip) 失败 errno=\(errno)")
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        var lastSend = Date.distantPast
        var recv = [UInt8](repeating: 0, count: 4096)
        var rounds = 0

        while Date() < deadline {
            // 每秒重发一轮，提高成功率（UDP 可能丢包）
            if Date().timeIntervalSince(lastSend) > 1.0 {
                for t in targets { sendBroadcast(to: t) }
                lastSend = Date()
                rounds += 1
            }

            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                    recvfrom(fd, &recv, recv.count, 0, sp, &fromLen)
                }
            }
            guard n > 0 else { continue }

            let data = Data(recv[0..<n])
            guard let text = String(data: data, encoding: .utf8) else { continue }
            let fields = text.components(separatedBy: ":")
            guard fields.count >= 4 else { continue }
            // 只接受角色为 TV 的响应
            guard fields[3] == "TV" else { continue }

            let ip = ipString(from: from) ?? ""
            guard !ip.isEmpty else { continue }
            let name = fields[2]
            if found[ip] == nil {
                found[ip] = Device(name: name, host: ip)
                log("TCL ← 发现 \(name) @ \(ip)")
            }
        }

        if found.isEmpty {
            log("TCL ← 未收到 6537 响应（共广播 \(rounds) 轮）")
        }
        return Array(found.values)
    }

    private static func ipString(from addr: sockaddr_in) -> String? {
        var a = addr.sin_addr
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &a, &buf, socklen_t(buf.count)) != nil else { return nil }
        return String(cString: buf)
    }

    // MARK: - 连接与握手

    func connect(host: String, completion: @escaping (Bool) -> Void) {
        connection?.cancel()
        recvBuffer.removeAll()
        useAES = false
        hasConnected = false
        closedIntentionally = false

        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: 6553)!,
            using: .tcp
        )
        connection = conn

        var finished = false
        let lock = NSLock()

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.sendRaw("159>>\(self.clientName)>>1>>\(self.clientID)>>1")
                self.receiveFrame { frame in
                    lock.lock()
                    defer { lock.unlock() }
                    guard !finished else { return }
                    finished = true
                    if let frame = frame, let text = String(data: frame, encoding: .utf8) {
                        let fields = text.components(separatedBy: ">>")
                        if fields.count > 6, fields[6] == "1" {
                            self.useAES = true
                        }
                        self.hasConnected = true
                        self.beginReceiveLoop()
                        completion(true)
                    } else {
                        completion(false)
                    }
                }
            case .failed, .cancelled:
                lock.lock()
                let wasFinished = finished
                finished = true
                lock.unlock()
                if !wasFinished {
                    completion(false)
                } else if self.hasConnected {
                    // 已连接后断开（电视关机 / 断网 / 系统挂起）
                    self.notifyDisconnect()
                }
            default:
                break
            }
        }
        conn.start(queue: queue)

        // 连接超时保护：电视关机时 TCP 可能长时间处于 waiting 状态，
        // 没有这一步会让上层重连循环卡死。
        queue.asyncAfter(deadline: .now() + 4.0) {
            lock.lock()
            let already = finished
            if !already { finished = true }
            lock.unlock()
            if !already {
                conn.cancel()
                completion(false)
            }
        }
    }

    // MARK: - 发送按键

    func sendKey(_ key: Key) {
        send("149>>\(key.rawValue)")
    }

    func disconnect() {
        closedIntentionally = true
        connection?.cancel()
        connection = nil
    }

    /// 通知上层：连接意外断开（电视关机 / 断网 / App 被挂起）
    private func notifyDisconnect() {
        guard hasConnected, !closedIntentionally else { return }
        hasConnected = false
        DispatchQueue.main.async { [weak self] in
            self?.onDisconnect?()
        }
    }

    // MARK: - 内部

    private func send(_ text: String) {
        guard let payload = text.data(using: .utf8) else { return }
        var out = payload
        if useAES, let encrypted = TCLAES.encrypt(payload) {
            out = encrypted
        }
        sendFrame(out)
    }

    private func sendRaw(_ text: String) {
        guard let payload = text.data(using: .utf8) else { return }
        sendFrame(payload)
    }

    private func sendFrame(_ payload: Data) {
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(payload)
        connection?.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func beginReceiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] _, _, isComplete, error in
            guard let self = self else { return }
            if error != nil || isComplete {
                self.notifyDisconnect()
                return
            }
            self.beginReceiveLoop()
        }
    }

    private func receiveFrame(completion: @escaping (Data?) -> Void) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { completion(nil); return }
            if let data = data {
                self.recvBuffer.append(data)
            }
            if self.recvBuffer.count >= 4 {
                let length = self.recvBuffer.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
                if self.recvBuffer.count >= 4 + Int(length) {
                    let payload = self.recvBuffer.subdata(in: 4..<(4 + Int(length)))
                    self.recvBuffer.removeSubrange(0..<(4 + Int(length)))
                    completion(payload)
                    return
                }
            }
            if error != nil || isComplete {
                completion(nil)
            } else {
                self.receiveFrame(completion: completion)
            }
        }
    }
}

// MARK: - AES-128-CBC（与 TCL 官方协议一致的固定密钥/IV）

private enum TCLAES {
    static let key: [UInt8] = Array("tnscreentnscreen".utf8)
    static let iv: [UInt8] = [
        0x12, 0x34, 0x56, 0x78, 0x90, 0xAB, 0xCD, 0xEF,
        0x12, 0x34, 0x56, 0x78, 0x90, 0xAB, 0xCD, 0xEF
    ]

    static func encrypt(_ data: Data) -> Data? {
        crypt(data, op: CCOperation(kCCEncrypt))
    }

    private static func crypt(_ data: Data, op: CCOperation) -> Data? {
        var outLength = 0
        var out = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
        let status: CCCryptorStatus = data.withUnsafeBytes { dataBuf in
            key.withUnsafeBytes { keyBuf in
                iv.withUnsafeBytes { ivBuf in
                    out.withUnsafeMutableBytes { outBuf in
                        CCCrypt(
                            op,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuf.baseAddress, key.count,
                            ivBuf.baseAddress,
                            dataBuf.baseAddress, data.count,
                            outBuf.baseAddress, outBuf.count,
                            &outLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return Data(bytes: out, count: outLength)
    }
}
