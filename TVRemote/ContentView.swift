//
//  ContentView.swift
//  TVRemote
//
//  主界面：状态栏 + 遥控器 + 设备列表 + 配对输入
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var controller: RemoteController
    @State private var showDevices = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if controller.state == .connected {
                    RemotePadView()
                } else {
                    placeholderView
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
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: statusIcon)
                .font(.system(size: 56))
                .foregroundColor(statusColor)
            Text(controller.message)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            if controller.state == .disconnected {
                Button("选择电视") {
                    showDevices = true
                }
                .buttonStyle(.borderedProminent)
            }
            Button("扫描内网电视") {
                controller.refresh()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
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
                                VStack(alignment: .leading) {
                                    Text(device.name).foregroundColor(.primary)
                                    Text(device.host).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(device.kind == .tcl ? "TCL" : "Google TV")
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

                if !controller.currentDeviceName.isEmpty && controller.currentDeviceName != "未连接" {
                    Section {
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
