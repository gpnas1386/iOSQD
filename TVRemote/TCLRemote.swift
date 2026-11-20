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
        case enter = 68
    }

    struct Device {
        let name: String
        let host: String
        var id: String { host }
    }

    /// 单次连接的状态容器。
    /// 每条 TCP 连接独立持有，避免旧连接的回调污染新连接的状态
    /// （之前把 finished / hasConnected 放在实例上，重连时旧回调会把新连接误判为断开）。
    private final class Session {
        let conn: NWConnection
        var handshakeDone = false
        var completed = false
        var cancelledByUs = false
        init(conn: NWConnection) { self.conn = conn }
    }

    private let clientName: String
    private let clientID: String
    private let queue = DispatchQueue(label: "tvremote.tcl")

    private var session: Session?
    private var recvBuffer = Data()
    private var useAES = false

    /// T-Cast 心跳：`150>>` / 电视回 `150>>YES`。
    /// 电视约 20 秒收不到任何流量就会主动断开，必须每 5 秒发一次保活。
    private var heartbeatTimer: DispatchSourceTimer?
    private var lastActivity = Date()
    private static let heartbeatInterval: TimeInterval = 5
    private static let idleTimeout: TimeInterval = 35

    /// 连接意外断开时回调（主动 disconnect 不触发），参数为断开原因
    var onDisconnect: ((String) -> Void)?
    /// 收到电视端主动下发的数据（用于诊断，判断电视为何断开）
    var onIncoming: ((String) -> Void)?

    private(set) var connectedAt: Date?
    private var hasConnected = false
    /// 相同内容的消息只上报前几次，避免心跳刷屏
    private var reportedMessages: [String: Int] = [:]

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

    func connect(host: String, timeout: TimeInterval = 5, completion: @escaping (Bool) -> Void) {
        // 清掉上一条连接，避免两条连接同时抢占电视（TCL 一般只允许一个遥控会话）
        closeCurrent(markIntentional: true)

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        // TCP 层保活：避免 NAT / 路由器回收空闲长连接
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        tcp.connectionTimeout = Int(timeout)

        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: 6553)!,
            using: NWParameters(tls: nil, tcp: tcp)
        )
        let s = Session(conn: conn)
        session = s
        recvBuffer.removeAll()
        useAES = false
        hasConnected = false
        connectedAt = nil
        reportedMessages.removeAll()

        conn.stateUpdateHandler = { [weak self, weak s] state in
            // 只处理「当前这条」连接的回调：旧连接被 cancel 后的迟到回调必须丢弃，
            // 否则会把刚建立的新连接误判为「断开」。
            guard let self = self, let s = s, self.session === s else { return }
            switch state {
            case .ready:
                self.connectedAt = Date()
                self.sendRaw("159>>\(self.clientName)>>1>>\(self.clientID)>>1")
                self.readHandshake(session: s, completion: completion)

            case .failed(let error):
                if !s.handshakeDone {
                    self.finishHandshake(session: s, ok: false, completion: completion)
                    self.reportDisconnect(reason: "连接失败：\(error.localizedDescription)", session: s)
                } else {
                    self.reportDisconnect(reason: "网络错误：\(error.localizedDescription)", session: s)
                }

            case .cancelled:
                if !s.handshakeDone {
                    self.finishHandshake(session: s, ok: false, completion: completion)
                } else {
                    self.reportDisconnect(reason: s.cancelledByUs ? "" : "连接被关闭", session: s)
                }

            default:
                break
            }
        }
        conn.start(queue: queue)

        // 连接到电视关机时 TCP 可能长时间处于 waiting，没有超时会让上层重连循环卡死
        queue.asyncAfter(deadline: .now() + timeout) { [weak self, weak s] in
            guard let self = self, let s = s, self.session === s else { return }
            guard !s.handshakeDone, !s.completed else { return }
            s.cancelledByUs = true
            conn.cancel()
            self.finishHandshake(session: s, ok: false, completion: completion)
        }
    }

    /// 握手只允许结算一次，超时 / 失败 / 成功三者互斥
    private func finishHandshake(session s: Session, ok: Bool, completion: @escaping (Bool) -> Void) {
        guard !s.completed else { return }
        s.completed = true
        s.handshakeDone = true
        completion(ok)
    }

    private func readHandshake(session s: Session, completion: @escaping (Bool) -> Void) {
        s.conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak s] data, _, isComplete, error in
            guard let self = self, let s = s, self.session === s else { return }
            if let data = data, !data.isEmpty {
                self.recvBuffer.append(data)
            }
            guard self.recvBuffer.count >= 4 else {
                if error != nil || isComplete {
                    self.finishHandshake(session: s, ok: false, completion: completion)
                } else {
                    self.readHandshake(session: s, completion: completion)
                }
                return
            }
            let length = self.recvBuffer.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
            guard self.recvBuffer.count >= 4 + Int(length) else {
                if error != nil || isComplete {
                    self.finishHandshake(session: s, ok: false, completion: completion)
                } else {
                    self.readHandshake(session: s, completion: completion)
                }
                return
            }
            let payload = self.recvBuffer.subdata(in: 4..<(4 + Int(length)))
            self.recvBuffer.removeSubrange(0..<(4 + Int(length)))

            let text = String(data: payload, encoding: .utf8) ?? ""
            let fields = text.components(separatedBy: ">>")
            if fields.count > 6, fields[6] == "1" {
                self.useAES = true
            }
            self.hasConnected = true
            self.lastActivity = Date()
            self.finishHandshake(session: s, ok: true, completion: completion)
            self.startHeartbeat(session: s)
            self.startReceiveLoop(session: s)
        }
    }

    // MARK: - 发送按键

    func sendKey(_ key: Key) {
        send("149>>\(key.rawValue)")
    }

    /// 文本注入：T-Cast 的 IME 指令 `155>><text>`（UTF-8 明文，未加密时原样发送）。
    /// 前提：电视端必须先把光标落在可输入的框里（如搜索框），否则电视会忽略。
    /// 协议用 `>>` 分隔字段且没有转义规则，文本里的 `>>` 会导致解析歧义，这里替换掉。
    @discardableResult
    func sendText(_ text: String) -> Bool {
        var cleaned = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ">>", with: "> >")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, hasConnected else { return false }
        if cleaned.count > 200 {
            cleaned = String(cleaned.prefix(200))
        }
        send("155>>\(cleaned)")
        return true
    }

    /// 回车 / 确认（搜索框里触发搜索）
    func sendEnter() {
        sendKey(.enter)
    }

    func disconnect() {
        closeCurrent(markIntentional: true)
    }

    // MARK: - 内部

    /// 心跳保活：每 5 秒 `150>>`（电视回 `150>>YES`）。
    /// 连续 35 秒收不到任何回包就判定链路已死，主动断开交给上层重连（比等 TCP 超时快）。
    private func startHeartbeat(session s: Session) {
        stopHeartbeat()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.heartbeatInterval,
                       repeating: Self.heartbeatInterval)
        timer.setEventHandler { [weak self, weak s] in
            guard let self = self, let s = s, self.session === s, self.hasConnected else { return }
            if Date().timeIntervalSince(self.lastActivity) > Self.idleTimeout {
                self.reportDisconnect(reason: "电视长时间无响应（可能已关机或断网）", session: s)
                s.cancelledByUs = true
                s.conn.cancel()
                return
            }
            self.send("150>>")
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private func closeCurrent(markIntentional: Bool) {
        stopHeartbeat()
        if let s = session {
            s.cancelledByUs = markIntentional
            s.conn.cancel()
        }
        session = nil
        hasConnected = false
        connectedAt = nil
        recvBuffer.removeAll()
    }

    /// 只在「曾经握手成功」的连接上上报断线，且每条连接只报一次
    private func reportDisconnect(reason: String, session s: Session) {
        guard hasConnected, !s.cancelledByUs else { return }
        stopHeartbeat()
        hasConnected = false
        let uptime = connectedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        connectedAt = nil
        let text = reason.isEmpty ? "连接已断开" : reason
        DispatchQueue.main.async { [weak self] in
            self?.onDisconnect?("\(text)（本次连接存活 \(uptime) 秒）")
        }
    }

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
        session?.conn.send(content: frame, completion: .contentProcessed { _ in })
    }

    /// 握手后的接收循环：不断读取，解析电视下发的消息并上报（用于诊断断开原因）
    private func startReceiveLoop(session s: Session) {
        s.conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak s] data, _, isComplete, error in
            guard let self = self, let s = s, self.session === s else { return }
            if let data = data, !data.isEmpty {
                self.lastActivity = Date()
                self.recvBuffer.append(data)
                self.drainIncoming(session: s)
            }
            if let error = error {
                self.reportDisconnect(reason: "读取失败：\(error.localizedDescription)", session: s)
                return
            }
            if isComplete {
                self.reportDisconnect(reason: "电视主动关闭了连接", session: s)
                return
            }
            self.startReceiveLoop(session: s)
        }
    }

    /// 按 4 字节长度拆帧；读不出合法帧时退化为文本上报，避免 buffer 越积越多
    private func drainIncoming(session s: Session) {
        var guardCount = 0
        while recvBuffer.count >= 4, guardCount < 32 {
            guardCount += 1
            let raw = recvBuffer.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
            let length = Int(raw)
            guard length > 0, length <= 65535 else {
                reportIncoming(recvBuffer.prefix(80))
                recvBuffer.removeAll()
                return
            }
            guard recvBuffer.count >= 4 + length else { return }
            let payload = recvBuffer.subdata(in: 4..<(4 + length))
            recvBuffer.removeSubrange(0..<(4 + length))
            reportIncoming(payload)
        }
    }

    private func reportIncoming(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 心跳回包（150>>YES）每 5 秒一次，不写日志避免刷屏
        if trimmed.hasPrefix("150>>") { return }
        let shown = trimmed.count > 60 ? String(trimmed.prefix(60)) + "…" : trimmed
        let count = (reportedMessages[shown] ?? 0) + 1
        reportedMessages[shown] = count
        guard count <= 3 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onIncoming?("TCL ← 收到「\(shown)」" + (count > 1 ? " ×\(count)" : ""))
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
