//
//  RemoteController.swift
//  TVRemote
//
//  核心控制器：mDNS 设备发现 + Android TV Remote v2 配对 + 遥控命令
//  协议实现依据 Android TV Remote Protocol v2 公开规范。
//

import Foundation
import Network
import Security
import CryptoKit
import Darwin
import UIKit

@MainActor
final class RemoteController: NSObject, ObservableObject {
    enum State: Equatable {
        case searching
        case connecting
        case waitingForPIN
        case connected
        case disconnected
        case failed(String)
    }

    enum ProtocolKind {
        case googleTV
        case tcl
        case unknown
    }

    struct Device: Identifiable, Hashable {
        let name: String
        let host: String
        let kind: ProtocolKind
        var ports: [UInt16] = []
        var id: String { host }

        var protocolLabel: String {
            switch kind {
            case .tcl: return "TCL"
            case .googleTV: return "Google TV"
            case .unknown:
                return ports.isEmpty ? "未识别" : PortScanner.inferProtocol(ports)
            }
        }
    }

    @Published var devices: [Device] = []
    @Published var state: State = .searching
    @Published var currentDeviceName = "未连接"
    @Published var currentApp: String?
    @Published var showPairingSheet = false
    @Published var message = "正在搜索内网电视…"

    /// 诊断日志（首屏可见，用于定位「为什么扫不到」）
    @Published var logs: [String] = []
    /// 各路发现渠道的状态摘要
    @Published var scanStatus: [String: String] = [:]
    /// 本机 Wi-Fi 地址
    @Published var wifiAddress = ""
    /// 扫描是否进行中
    @Published var isScanning = false
    /// 是否正在自动重连（UI 显示"重连中"）
    @Published var autoReconnecting = false
    /// 是否启用断线自动重连（用户可关闭）
    @Published var autoReconnectEnabled = true

    private var reconnectTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?

    /// 当前是否使用 TCL 协议（TCL 协议不支持文本输入/应用启动/媒体键等）
    var isTCL: Bool { currentProtocol == .tcl }

    private let queue = DispatchQueue(label: "tvremote.network")
    private var browsers: [NetServiceBrowser] = []
    private var resolvingServices: [NetService] = []
    private var connection: NWConnection?
    private var tclRemote: TCLRemote?
    private var currentProtocol: ProtocolKind = .googleTV

    // Google TV 按键码 -> TCL 按键码映射
    private static let googleToTCL: [Int: TCLRemote.Key] = [
        19: .up, 20: .down, 21: .left, 22: .right, 23: .ok,
        4: .back, 3: .home, 82: .menu,
        24: .volUp, 25: .volDown, 164: .mute,
        166: .chUp, 167: .chDown,
        26: .power
    ]
    private var receiveBuffer = Data()
    private var mode: Mode = .remote
    private var identity: SecIdentity?
    private var serverCertificate: SecCertificate?
    private var currentHost = ""
    private var pairIfRejected = false
    private let features = 623
    private var imeCounter = 0
    private var imeFieldCounter = 0

    private enum Mode { case pairing, remote }

    override init() {
        super.init()
        identity = IdentityStore.loadIdentity()
        scanStatus = ["SSDP": "待扫描", "TCL": "待扫描", "Bonjour": "待扫描"]

        // 从后台回到前台时，若还没连上就自动重连（TCP 长连接会被系统挂断）
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                guard self.autoReconnectEnabled,
                      self.state != .connected,
                      !self.currentHost.isEmpty else { return }
                self.appendLog("回到前台，自动重连 \(self.currentHost)")
                self.startAutoReconnect(host: self.currentHost)
            }
        }

        if let saved = DeviceStore.load() {
            currentHost = saved.host
            currentDeviceName = saved.name
            appendLog("上次设备：\(saved.name) @ \(saved.host)（\(saved.kind)）")
            if saved.kind == "tcl" {
                // 关键优化：TCL 设备直接重连，不再依赖「多屏互动」触发的广播发现
                currentProtocol = .tcl
                appendLog("直接重连上次的 TCL 设备，跳过扫描")
                startAutoReconnect(host: saved.host)
            } else {
                connectRemote(host: saved.host, pairIfNeeded: true)
            }
            // 后台仍扫描一次，用于 IP 变化（DHCP 重新分配）时兜底
            startBrowsing()
        } else {
            startBrowsing()
        }
    }

    // MARK: - 发现

    func refresh() {
        devices.removeAll()
        scanStatus = ["SSDP": "进行中", "TCL": "进行中", "Bonjour": "进行中"]
        state = .searching
        message = "正在搜索内网电视…"
        appendLog("──────── 开始新一轮扫描 ────────")
        startBrowsing()
    }

    func startBrowsing() {
        for b in browsers { b.stop() }
        browsers.removeAll()
        resolvingServices.removeAll()
        isScanning = true

        // 0) 先报告网络环境，这是排查的第一手信息
        if let wifi = NetworkInfo.wifiInterface() {
            wifiAddress = wifi.address
            appendLog("本机 Wi-Fi \(wifi.name)：\(wifi.address) / \(wifi.netmask)"
                      + (wifi.broadcast.map { " 广播 \($0)" } ?? ""))
        } else {
            wifiAddress = ""
            appendLog("⚠️ 未检测到 Wi-Fi 接口（en0）")
        }
        if NetworkInfo.isCellularOnly() {
            appendLog("⚠️ 当前只有蜂窝网络，请连接与电视相同的 Wi-Fi")
        }

        // 1) SSDP（最通用，几乎所有电视都响应）
        SSDPDiscovery.scan(timeout: 3.5, log: { [weak self] text in
            self?.safeLog(text)
        }, completion: { [weak self] results in
            Task { @MainActor in
                guard let self = self else { return }
                self.scanStatus["SSDP"] = "\(results.count) 台"
                for r in results {
                    self.appendLog("SSDP ✓ \(r.name) @ \(r.host)")
                    self.mergeDevice(name: r.name, host: r.host, kind: .unknown)
                }
                if results.isEmpty {
                    self.appendLog("SSDP 无响应：可能路由器开了「AP 隔离 / 访客网络」，或电视未联网")
                }
            }
        })

        // 2) TCL 专有协议（UDP 6537）
        TCLRemote.discover(timeout: 4, log: { [weak self] text in
            self?.safeLog(text)
        }, completion: { [weak self] tclDevices in
            Task { @MainActor in
                guard let self = self else { return }
                self.scanStatus["TCL"] = "\(tclDevices.count) 台"
                for d in tclDevices {
                    self.mergeDevice(name: d.name, host: d.host, kind: .tcl)
                }
                // 电视重启后 IP 可能变化：重连中若发现新地址，切换过去
                if self.autoReconnecting,
                   let first = tclDevices.first,
                   first.host != self.currentHost {
                    self.appendLog("发现电视新地址 \(first.host)，切换重连目标")
                    self.currentHost = first.host
                    self.currentDeviceName = first.name
                    self.startAutoReconnect(host: first.host)
                }
            }
        })

        // 3) Bonjour（Google TV / Android TV）
        for type in ["_androidtvremote2._tcp.", "_androidtvremote._tcp."] {
            let b = NetServiceBrowser()
            b.delegate = self
            b.searchForServices(ofType: type, inDomain: "local.")
            browsers.append(b)
        }
        appendLog("Bonjour → 浏览 _androidtvremote2 / _androidtvremote")

        // 无论哪路先结束，6 秒后统一收尾
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self = self else { return }
            self.isScanning = false
            if self.devices.isEmpty {
                self.message = "未发现设备，请展开诊断日志查看详情"
                self.appendLog("扫描结束：未发现任何设备")
            } else {
                self.message = "发现 \(self.devices.count) 台设备，点「设备」选择"
                self.appendLog("扫描结束：共 \(self.devices.count) 台设备")
            }
        }
    }

    /// 合并同一 IP 的设备信息（协议优先级：tcl / googleTV > unknown）
    private func mergeDevice(name: String, host: String, kind: ProtocolKind) {
        if let idx = devices.firstIndex(where: { $0.host == host }) {
            let old = devices[idx]
            if old.kind == .unknown && kind != .unknown {
                devices[idx] = Device(name: name.isEmpty ? old.name : name,
                                      host: host, kind: kind, ports: old.ports)
            }
            return
        }
        devices.append(Device(name: name.isEmpty ? host : name, host: host,
                              kind: kind, ports: []))
        probePorts(for: host)
    }

    /// 对发现的 IP 做端口探测，判断它支持哪种遥控协议
    private func probePorts(for host: String) {
        PortScanner.probe(host: host) { [weak self] ports in
            Task { @MainActor in
                guard let self = self else { return }
                guard let idx = self.devices.firstIndex(where: { $0.host == host }) else { return }
                let old = self.devices[idx]
                self.devices[idx] = Device(name: old.name, host: host, kind: old.kind, ports: ports)
                let desc = PortScanner.describe(ports)
                self.appendLog("端口探测 \(host)：\(desc.isEmpty ? "无开放端口" : desc)")
            }
        }
    }

    // MARK: - 日志

    func appendLog(_ text: String) {
        let now = Date()
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
        let stamp = String(format: "%02d:%02d:%02d",
                           comps.hour ?? 0, comps.minute ?? 0, comps.second ?? 0)
        logs.append("[\(stamp)] \(text)")
        if logs.count > 200 {
            logs.removeFirst(logs.count - 200)
        }
    }

    /// 供后台线程安全写日志
    nonisolated private func safeLog(_ text: String) {
        Task { @MainActor in
            self.appendLog(text)
        }
    }

    // MARK: - 连接 / 配对

    func select(_ device: Device) {
        currentDeviceName = device.name
        currentHost = device.host
        switch device.kind {
        case .tcl:
            connectTCL(host: device.host)
        case .googleTV:
            connectRemote(host: device.host, pairIfNeeded: true)
        case .unknown:
            connectManually(device.host)
        }
    }

    func connectManually(_ raw: String) {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        currentHost = clean
        currentDeviceName = clean
        state = .connecting
        message = "正在探测 \(clean) …"
        appendLog("手动连接 \(clean)：开始端口探测")

        PortScanner.probe(host: clean) { [weak self] ports in
            Task { @MainActor in
                guard let self = self else { return }
                let desc = PortScanner.describe(ports)
                self.appendLog("探测结果：\(desc.isEmpty ? "全部端口关闭/被防火墙拦截" : desc)")

                if ports.contains(6553) {
                    self.appendLog("→ 命中 6553，使用 TCL 协议")
                    self.connectTCL(host: clean)
                } else if ports.contains(6466) {
                    self.appendLog("→ 命中 6466，使用 Google TV 协议")
                    self.connectRemote(host: clean, pairIfNeeded: true)
                } else if ports.contains(8060) {
                    self.state = .failed("检测到 8060 端口：这是 Roku 系统，暂不支持")
                    self.message = "这台电视是 Roku 系统，需要另一套协议"
                } else {
                    self.appendLog("→ 无已知遥控端口，回退尝试 TCL 协议")
                    self.connectTCL(host: clean)
                }
            }
        }
    }

    func submitPIN(_ pin: String) {
        let code = pin.uppercased().filter { $0.isHexDigit }
        guard code.count == 6 else {
            state = .failed("配对码需为 6 位（0-9、A-F）")
            return
        }
        guard let secret = pairingSecret(pin: code) else {
            state = .failed("配对码不匹配，请重新配对")
            return
        }
        showPairingSheet = false
        send(Polo.message(field: 40, payload: Proto.bytesField(1, secret)))
        message = "正在校验配对码…"
    }

    // MARK: - 遥控命令

    func sendKey(_ keyCode: Int) {
        guard state == .connected else { return }
        if currentProtocol == .tcl, let key = Self.googleToTCL[keyCode] {
            tclRemote?.sendKey(key)
            return
        }
        let inject = Proto.varintField(1, keyCode) + Proto.varintField(2, 3)
        send(Proto.message(field: 10, payload: inject))
    }

    func sendText(_ text: String) {
        guard state == .connected, !text.isEmpty else { return }
        guard currentProtocol != .tcl else { return } // TCL 协议暂不支持文本输入
        let last = max(text.utf16.count - 1, 0)
        let object = Proto.varintField(1, last) + Proto.varintField(2, last) + Proto.stringField(3, text)
        let edit = Proto.varintField(1, 1) + Proto.message(field: 2, payload: object)
        let batch = Proto.varintField(1, imeCounter) + Proto.varintField(2, imeFieldCounter) + Proto.message(field: 3, payload: edit)
        send(Proto.message(field: 21, payload: batch))
    }

    func launch(_ appID: String) {
        guard state == .connected, !appID.isEmpty else { return }
        guard currentProtocol != .tcl else { return } // TCL 协议暂不支持启动应用
        let link = appID.contains(":") ? appID : "market://launch?id=\(appID)"
        send(Proto.message(field: 90, payload: Proto.stringField(1, link)))
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        autoReconnecting = false
        connection?.cancel()
        connection = nil
        tclRemote?.onDisconnect = nil
        tclRemote?.disconnect()
        tclRemote = nil
        state = .disconnected
        currentApp = nil
        message = "已断开"
    }

    func forget() {
        disconnect()
        DeviceStore.clear()
        currentHost = ""
        currentDeviceName = "未连接"
        refresh()
    }

    // MARK: - 网络连接

    private func startPairing(host: String) {
        state = .waitingForPIN
        message = "电视上将显示 6 位配对码"
        open(host: host, port: 6467, mode: .pairing)
    }

    private func connectRemote(host: String, pairIfNeeded: Bool = false) {
        pairIfRejected = pairIfNeeded
        currentProtocol = .googleTV
        state = .connecting
        message = "正在连接 \(host) …"
        appendLog("Google TV → 连接 \(host):6466 (TLS)")
        open(host: host, port: 6466, mode: .remote)
    }

    private func connectTCL(host: String) {
        currentProtocol = .tcl
        currentHost = host
        startAutoReconnect(host: host)
    }

    /// 自动重连循环：失败每 3 秒重试，最多 40 次（约 2 分钟）
    /// 每 3 次失败回退做一次扫描，以防电视 DHCP 换了 IP。
    func startAutoReconnect(host: String) {
        reconnectTask?.cancel()
        guard autoReconnectEnabled else { return }
        reconnectTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            var attempt = 0
            while !Task.isCancelled {
                attempt += 1
                self.autoReconnecting = true
                self.state = .connecting
                self.message = attempt == 1 ? "正在连接 \(host) …" : "正在重连（第 \(attempt) 次）…"

                let tcl = TCLRemote()
                let ok: Bool = await withCheckedContinuation { cont in
                    tcl.connect(host: host) { result in
                        cont.resume(returning: result)
                    }
                }
                if Task.isCancelled { return }

                if ok {
                    self.tclRemote = tcl
                    self.currentProtocol = .tcl
                    self.state = .connected
                    self.autoReconnecting = false
                    self.message = "已连接，可以遥控了"
                    self.appendLog("TCL ✓ 连接成功（第 \(attempt) 次）")
                    self.saveDevice()
                    // 连接断开时自动进入重连
                    tcl.onDisconnect = { [weak self] in
                        Task { @MainActor in
                            guard let self = self else { return }
                            self.appendLog("TCL ✗ 连接已断开")
                            self.state = .disconnected
                            self.message = "连接断开，正在自动重连…"
                            if self.autoReconnectEnabled {
                                self.startAutoReconnect(host: self.currentHost)
                            }
                        }
                    }
                    return
                }

                self.appendLog("TCL ✗ 第 \(attempt) 次连接失败")
                if attempt % 3 == 0 {
                    self.appendLog("连续失败，回退扫描一次（电视 IP 可能已变化）")
                    self.startBrowsing()
                }
                if attempt >= 40 {
                    self.state = .failed("多次重连失败")
                    self.autoReconnecting = false
                    self.message = "无法连接电视，请确认电视已开机"
                    return
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func setAutoReconnect(_ enabled: Bool) {
        autoReconnectEnabled = enabled
        if enabled {
            if state != .connected && !currentHost.isEmpty {
                startAutoReconnect(host: currentHost)
            }
        } else {
            reconnectTask?.cancel()
            reconnectTask = nil
            autoReconnecting = false
            appendLog("已关闭自动重连")
        }
    }

    private func open(host: String, port: UInt16, mode: Mode) {
        guard let identity = identity else {
            state = .failed("配对证书缺失")
            return
        }
        connection?.cancel()
        receiveBuffer.removeAll()
        self.mode = mode

        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_local_identity(options, sec_identity_create(identity)!)
        sec_protocol_options_set_verify_block(options, { [weak self] _, trust, complete in
            if let secTrust = sec_trust_copy_ref(trust).takeRetainedValue() as SecTrust?,
               let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate] {
                self?.serverCertificate = chain.first
            }
            complete(true)
        }, queue)

        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: parameters
        )
        connection = conn
        conn.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in self?.handleConnectionState(newState) }
        }
        conn.start(queue: queue)
    }

    private func handleConnectionState(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            receiveNext()
            if mode == .pairing {
                send(Polo.pairingRequest(clientName: UIDevice.current.name))
            }
        case .failed(let error):
            if mode == .remote && pairIfRejected && !currentHost.isEmpty {
                pairIfRejected = false
                startPairing(host: currentHost)
            } else if mode == .remote && !currentHost.isEmpty {
                state = .disconnected
                message = "连接断开，点设备重新连接"
            } else {
                state = .failed("无法连接：\(error.localizedDescription)")
            }
        case .cancelled:
            break
        default:
            break
        }
    }

    private func receiveNext() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self = self else { return }
            Task { @MainActor in
                if let data = data {
                    self.receiveBuffer.append(data)
                    self.consumeFrames()
                }
                if error == nil && !complete {
                    self.receiveNext()
                }
            }
        }
    }

    private func consumeFrames() {
        while let (length, prefix) = Proto.readVarint(receiveBuffer, at: 0),
              receiveBuffer.count >= prefix + length {
            let payload = receiveBuffer.subdata(in: prefix..<(prefix + length))
            receiveBuffer.removeSubrange(0..<(prefix + length))
            handle(payload)
        }
    }

    private func handle(_ payload: Data) {
        let fields = Proto.fields(payload)

        if mode == .pairing {
            if fields[11] != nil {
                send(Polo.options())
            } else if fields[20] != nil {
                send(Polo.configuration())
            } else if fields[31] != nil {
                state = .waitingForPIN
                showPairingSheet = true
                message = "请输入电视上显示的 6 位配对码"
            } else if fields[41] != nil {
                saveDevice()
                connection?.cancel()
                connectRemote(host: currentHost)
            }
            return
        }

        // remote 模式
        if let configure = fields[1] {
            let supported = Proto.intField(configure, number: 1) ?? features
            let active = supported & features
            let info = Proto.varintField(3, 1)
                + Proto.stringField(4, "1")
                + Proto.stringField(5, "atvremote")
                + Proto.stringField(6, "1.0.0")
            let cfg = Proto.varintField(1, active) + Proto.message(field: 2, payload: info)
            send(Proto.message(field: 1, payload: cfg))
        } else if let setActive = fields[2] {
            let active = Proto.intField(setActive, number: 1) ?? features
            send(Proto.message(field: 2, payload: Proto.varintField(1, active & features)))
        } else if let ping = fields[8] {
            let value = Proto.intField(ping, number: 1) ?? 0
            send(Proto.message(field: 9, payload: Proto.varintField(1, value)))
        } else if let ime = fields[21] {
            imeCounter = Proto.intField(ime, number: 1) ?? imeCounter
            imeFieldCounter = Proto.intField(ime, number: 2) ?? imeFieldCounter
        } else if fields[40] != nil {
            saveDevice()
            state = .connected
            message = "已连接，可以遥控了"
        }
    }

    private func send(_ payload: Data) {
        var frame = Proto.varint(payload.count)
        frame.append(payload)
        connection?.send(content: frame, completion: .contentProcessed { _ in })
    }

    // MARK: - 配对挑战计算

    private func pairingSecret(pin: String) -> Data? {
        guard let identity = identity,
              let clientCert = IdentityStore.certificate(from: identity),
              let serverCert = serverCertificate,
              let clientKey = SecCertificateCopyKey(clientCert),
              let serverKey = SecCertificateCopyKey(serverCert),
              let clientRSA = ASN1.rsaNumbers(clientKey),
              let serverRSA = ASN1.rsaNumbers(serverKey),
              let pinBytes = Data(hexString: String(pin.dropFirst(2))) else {
            return nil
        }
        var source = Data()
        source.append(clientRSA.modulus)
        source.append(clientRSA.exponent)
        source.append(serverRSA.modulus)
        source.append(serverRSA.exponent)
        source.append(pinBytes)
        let digest = Data(SHA256.hash(data: source))
        guard digest.first == UInt8(pin.prefix(2), radix: 16) else { return nil }
        return digest
    }

    private func saveDevice() {
        guard !currentHost.isEmpty else { return }
        let kind = currentProtocol == .tcl ? "tcl" : "google"
        DeviceStore.save(host: currentHost, name: currentDeviceName, kind: kind)
    }
}

// MARK: - 配对协议（Polo）

private enum Polo {
    static func base() -> Data {
        Proto.varintField(1, 2) + Proto.varintField(2, 200)
    }

    static func pairingRequest(clientName: String) -> Data {
        base() + Proto.message(
            field: 10,
            payload: Proto.stringField(1, "atvremote") + Proto.stringField(2, clientName)
        )
    }

    static func options() -> Data {
        let encoding = Proto.varintField(1, 3) + Proto.varintField(2, 6)
        return base() + Proto.message(
            field: 20,
            payload: Proto.message(field: 1, payload: encoding) + Proto.varintField(3, 1)
        )
    }

    static func configuration() -> Data {
        let encoding = Proto.varintField(1, 3) + Proto.varintField(2, 6)
        return base() + Proto.message(
            field: 30,
            payload: Proto.message(field: 1, payload: encoding) + Proto.varintField(2, 1)
        )
    }

    static func message(field: Int, payload: Data) -> Data {
        base() + Proto.message(field: field, payload: payload)
    }
}

// MARK: - 设备持久化（Keychain）

private enum DeviceStore {
    private static let service = "com.tvremote.device"
    private static let account = "last-device"

    struct Saved {
        let host: String
        let name: String
        let kind: String   // "tcl" / "google"
    }

    static func save(host: String, name: String, kind: String) {
        guard let payload = try? JSONSerialization.data(
            withJSONObject: ["host": host, "name": name, "kind": kind]
        ) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes = [kSecValueData as String: payload]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = payload
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func load() -> Saved? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let host = object["host"],
              let name = object["name"] else {
            return nil
        }
        return Saved(host: host, name: name, kind: object["kind"] ?? "google")
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Bonjour 发现

extension RemoteController: NetServiceBrowserDelegate, NetServiceDelegate {
    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        Task { @MainActor in
            self.resolvingServices.append(service)
            service.delegate = self
            service.resolve(withTimeout: 5)
        }
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses else { return }
        for address in addresses {
            if let host = Self.hostString(from: address) {
                Task { @MainActor in
                    let device = Device(name: sender.name, host: host, kind: .googleTV)
                    if !self.devices.contains(where: { $0.host == host }) {
                        self.devices.append(device)
                    }
                }
                break
            }
        }
    }

    nonisolated private static func hostString(from data: Data) -> String? {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return nil }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(base, socklen_t(data.count), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard result == 0 else { return nil }
            return String(cString: host).components(separatedBy: "%").first
        }
    }
}
