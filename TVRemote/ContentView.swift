//
//  ContentView.swift
//  TVRemote
//
//  主界面：状态栏 + 遥控器 + 设备列表 + 配对输入
//

import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var controller: RemoteController
    @State private var showDevices = false
    @State private var showLogs = false
    @State private var logsExpanded = false
    @State private var toastText: String?
    @State private var manualIP = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if controller.shouldShowRemotePad {
                    VStack(spacing: 0) {
                        if let banner = controller.linkBanner {
                            linkBannerView(banner)
                        }
                        RemotePadView()
                    }
                } else {
                    placeholderView
                }

                if let toast = toastText {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.78))
                            .cornerRadius(18)
                            .padding(.bottom, 32)
                            .transition(.opacity)
                    }
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle(controller.currentDeviceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        controller.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(controller.isScanning)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showDevices = true
                    } label: {
                        Image(systemName: "tv.badge.wifi")
                    }
                }
            }
            .sheet(isPresented: $showDevices) {
                DeviceListView()
                    .environmentObject(controller)
            }
            .sheet(isPresented: $controller.showPairingSheet) {
                PairingView()
                    .environmentObject(controller)
            }
            .sheet(isPresented: $showLogs) {
                LogView()
                    .environmentObject(controller)
            }
        }
    }

    // MARK: 顶部链路横幅

    private func linkBannerView(_ banner: (text: String, isError: Bool)) -> some View {
        HStack(spacing: 8) {
            if banner.isError {
                Image(systemName: "exclamationmark.triangle.fill")
            } else {
                ProgressView()
                    .scaleEffect(0.65)
                    .tint(.orange)
            }
            Text(banner.text)
                .font(.caption)
                .lineLimit(2)
            Spacer(minLength: 6)
            if banner.isError {
                Button("重试") { controller.retryNow() }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.22))
                    .cornerRadius(8)
            }
        }
        .foregroundColor(banner.isError ? .white : .primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(banner.isError ? Color.red.opacity(0.9) : Color.orange.opacity(0.16))
    }

    private func showToast(_ text: String) {
        withAnimation { toastText = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { toastText = nil }
        }
    }

    private var placeholderView: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerBlock
                networkCard
                manualCard
                actionRow
                logCard
                Spacer(minLength: 12)
            }
            .padding()
        }
    }

    private var headerBlock: some View {
        VStack(spacing: 10) {
            Image(systemName: statusIcon)
                .font(.system(size: 44))
                .foregroundColor(statusColor)
            Text(controller.message)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            if controller.isScanning {
                ProgressView()
                    .scaleEffect(0.8)
            }
            Text("v\(appVersion)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("网络状态", systemImage: "wifi")
                .font(.subheadline.bold())

            HStack {
                Text("本机 Wi-Fi IP")
                Spacer()
                Text(controller.wifiAddress.isEmpty ? "未连接" : controller.wifiAddress)
                    .foregroundColor(controller.wifiAddress.isEmpty ? .red : .secondary)
            }
            .font(.caption)

            ForEach(["SSDP", "TCL", "Bonjour"], id: \.self) { key in
                HStack {
                    Text(key)
                    Spacer()
                    Text(controller.scanStatus[key] ?? "—")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            }

            Divider().padding(.vertical, 2)

            Toggle(isOn: Binding(
                get: { controller.autoReconnectEnabled },
                set: { controller.setAutoReconnect($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("断线自动重连")
                        .font(.caption)
                    Text("电视关机再开、或 App 切回前台时自动重连，无需再去电视开多屏互动")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("手动连接")
                .font(.subheadline.bold())
            Text("在电视「设置 → 网络 / 关于」里查看 IP，直接输入即可")
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                TextField("如 192.168.1.100", text: $manualIP)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(8)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(8)
                Button("连接") {
                    let ip = manualIP
                    manualIP = ""
                    controller.connectManually(ip)
                }
                .buttonStyle(.borderedProminent)
                .disabled(manualIP.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                controller.refresh()
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(controller.isScanning)

            Button {
                showDevices = true
            } label: {
                Label("设备 \(controller.devices.count)", systemImage: "tv")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    withAnimation { logsExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: logsExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Label("诊断日志（\(controller.logs.count)）",
                              systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    UIPasteboard.general.string = controller.exportLogText()
                    showToast("日志已复制到剪贴板")
                } label: {
                    Label("复制", systemImage: "doc.on.doc").font(.caption)
                }
                .buttonStyle(.borderless)

                Button {
                    showLogs = true
                } label: {
                    Text("全部").font(.caption)
                }
                .buttonStyle(.borderless)
            }

            if logsExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    if controller.logs.isEmpty {
                        Text("暂无日志").font(.caption2).foregroundColor(.secondary)
                    }
                    ForEach(Array(controller.logs.suffix(80).enumerated()), id: \.offset) { pair in
                        Text(pair.element)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var statusIcon: String {
        switch controller.state {
        case .searching: return "antenna.radiowaves.left.and.right"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .waitingForPIN: return "key"
        case .connected: return "checkmark.circle"
        case .disconnected: return "tv"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch controller.state {
        case .connected: return .green
        case .failed: return .red
        case .waitingForPIN: return .orange
        default: return .gray
        }
    }
}

// MARK: - 设备列表

struct DeviceListView: View {
    @EnvironmentObject var controller: RemoteController
    @Environment(\.dismiss) private var dismiss
    @State private var manualIP = ""

    var body: some View {
        NavigationStack {
            List {
                Section("已发现设备") {
                    if controller.devices.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("暂未发现电视")
                                .foregroundColor(.secondary)
                            Text("排查建议：\n1. 手机与电视连同一 Wi-Fi，路由器勿开「AP 隔离」\n2. 电视需开启「远程控制 / Android TV Remote」功能\n3. 检查 设置 → 隐私与安全 → 本地网络，允许本 App\n4. 也可在下方手动输入电视 IP 直连")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    ForEach(controller.devices) { device in
                        Button {
                            dismiss()
                            controller.select(device)
                        } label: {
                            HStack {
                                Image(systemName: "tv")
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name).foregroundColor(.primary)
                                    Text(device.host).font(.caption).foregroundColor(.secondary)
                                    if !device.ports.isEmpty {
                                        Text(device.ports.map { String($0) }.joined(separator: " / "))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Text(device.protocolLabel)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }

                Section("手动连接") {
                    HStack {
                        TextField("输入电视 IP，如 192.168.1.100", text: $manualIP)
                            .keyboardType(.decimalPad)
                            .autocapitalization(.none)
                        Button("连接") {
                            dismiss()
                            controller.connectManually(manualIP)
                        }
                        .disabled(manualIP.isEmpty)
                    }
                }

                Section("设置") {
                    Toggle(isOn: Binding(
                        get: { controller.hapticsEnabled },
                        set: { newValue in
                            controller.hapticsEnabled = newValue
                            if newValue { Haptics.key() }   // 开启时立刻给一次手感
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("按键震动反馈")
                            Text("按遥控键时轻微震动；长按连发做了节流，不会震得手麻")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if !controller.currentDeviceName.isEmpty && controller.currentDeviceName != "未连接" {
                    Section {
                        Button("断开连接") {
                            controller.disconnect()
                            dismiss()
                        }
                        Button("断开并忘记设备", role: .destructive) {
                            controller.forget()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        controller.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 日志全文（可选中 / 复制 / 分享）

struct LogView: View {
    @EnvironmentObject var controller: RemoteController
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(controller.exportLogText())
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("诊断日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = controller.exportLogText()
                        copied = true
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            copied = false
                        }
                    } label: {
                        Label(copied ? "已复制" : "复制",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    ShareLink(item: controller.exportLogText()) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

// MARK: - 配对输入

struct PairingView: View {
    @EnvironmentObject var controller: RemoteController
    @State private var pin = ""

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("输入配对码")
                .font(.title2.bold())
            Text("请在电视屏幕上查看显示的 6 位配对码（字母或数字），输入到下方完成配对。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            TextField("如 A1B2C3", text: $pin)
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .onChange(of: pin) { newValue in
                    let filtered = newValue.uppercased().filter { $0.isHexDigit }
                    if filtered != newValue.uppercased() {
                        pin = filtered
                    }
                    if pin.count > 6 {
                        pin = String(pin.prefix(6))
                    }
                }

            Button {
                controller.submitPIN(pin)
            } label: {
                Text("确认配对")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(pin.count == 6 ? Color.accentColor : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(pin.count != 6)

            Button("取消") {
                controller.showPairingSheet = false
            }
            .foregroundColor(.secondary)
        }
        .padding(24)
    }
}
