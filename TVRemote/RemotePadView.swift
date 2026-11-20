//
//  RemotePadView.swift
//  TVRemote
//
//  遥控器界面
//

import SwiftUI
import UIKit

struct RemotePadView: View {
    @EnvironmentObject var controller: RemoteController
    @State private var text = ""
    @State private var appID = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                powerSection
                dpadSection
                systemSection
                volumeChannelSection
                if controller.isTCL {
                    TextInputSection()
                } else {
                    mediaSection
                    numberSection
                    inputSection
                    appSection
                }
            }
            .padding()
        }
    }

    // MARK: 电源

    private var powerSection: some View {
        Button {
            controller.sendKey(26)
        } label: {
            Image(systemName: "power")
                .font(.system(size: 26))
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Color.red.opacity(0.85)))
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: 方向键圆盘

    private var dpadSection: some View {
        VStack(spacing: 12) {
            RepeatKeyButton(icon: "chevron.up", keyCode: 19) { controller.sendKey($0) }
                .frame(width: 72, height: 72)
            HStack(spacing: 12) {
                RepeatKeyButton(icon: "chevron.left", keyCode: 21) { controller.sendKey($0) }
                    .frame(width: 72, height: 72)
                Button {
                    controller.sendKey(23)
                } label: {
                    Text("OK")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(Color.accentColor))
                }
                .buttonStyle(ScaleButtonStyle())
                RepeatKeyButton(icon: "chevron.right", keyCode: 22) { controller.sendKey($0) }
                    .frame(width: 72, height: 72)
            }
            RepeatKeyButton(icon: "chevron.down", keyCode: 20) { controller.sendKey($0) }
                .frame(width: 72, height: 72)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 返回 / 主页 / 菜单

    private var systemSection: some View {
        HStack(spacing: 12) {
            KeyButton(icon: "arrow.uturn.backward", label: "返回", keyCode: 4) { controller.sendKey($0) }
            KeyButton(icon: "house.fill", label: "主页", keyCode: 3) { controller.sendKey($0) }
            KeyButton(icon: "line.3.horizontal", label: "菜单", keyCode: 82) { controller.sendKey($0) }
        }
    }

    // MARK: 音量 / 频道

    private var volumeChannelSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                RepeatKeyButton(icon: "speaker.minus.fill", label: "音量−", keyCode: 25) { controller.sendKey($0) }
                KeyButton(icon: "speaker.slash.fill", label: "静音", keyCode: 164) { controller.sendKey($0) }
                RepeatKeyButton(icon: "speaker.plus.fill", label: "音量+", keyCode: 24) { controller.sendKey($0) }
            }
            HStack(spacing: 12) {
                RepeatKeyButton(icon: "chevron.down.circle", label: "频道−", keyCode: 167) { controller.sendKey($0) }
                if !controller.isTCL {
                    KeyButton(icon: "rectangle.connected.to.line.below", label: "输入源", keyCode: 178) { controller.sendKey($0) }
                }
                RepeatKeyButton(icon: "chevron.up.circle", label: "频道+", keyCode: 166) { controller.sendKey($0) }
            }
        }
    }

    // MARK: 媒体

    private var mediaSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                KeyButton(icon: "backward.fill", label: "快退", keyCode: 89) { controller.sendKey($0) }
                KeyButton(icon: "backward.end.fill", label: "上一个", keyCode: 88) { controller.sendKey($0) }
                KeyButton(icon: "playpause.fill", label: "播放", keyCode: 85) { controller.sendKey($0) }
                KeyButton(icon: "forward.end.fill", label: "下一个", keyCode: 87) { controller.sendKey($0) }
                KeyButton(icon: "forward.fill", label: "快进", keyCode: 90) { controller.sendKey($0) }
            }
            HStack(spacing: 12) {
                KeyButton(icon: "magnifyingglass", label: "搜索", keyCode: 84) { controller.sendKey($0) }
                KeyButton(icon: "gearshape.fill", label: "设置", keyCode: 176) { controller.sendKey($0) }
                KeyButton(icon: "mic.fill", label: "语音", keyCode: 219) { controller.sendKey($0) }
            }
        }
    }

    // MARK: 数字键

    private var numberSection: some View {
        let numbers: [(String, Int)] = [
            ("1", 8), ("2", 9), ("3", 10),
            ("4", 11), ("5", 12), ("6", 13),
            ("7", 14), ("8", 15), ("9", 16),
            ("0", 7)
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(numbers, id: \.1) { item in
                Button {
                    controller.sendKey(item.1)
                } label: {
                    Text(item.0)
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
    }

    // MARK: 文本输入

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文字输入").font(.caption).foregroundColor(.secondary)
            HStack(spacing: 10) {
                TextField("发送文字到电视", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Button("发送") {
                    controller.sendText(text)
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.isEmpty)
            }
        }
    }

    // MARK: 打开应用

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("打开应用 / 链接").font(.caption).foregroundColor(.secondary)
            HStack(spacing: 10) {
                TextField("包名或网址，如 youtube", text: $appID)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                Button("打开") {
                    controller.launch(appID)
                }
                .buttonStyle(.bordered)
                .disabled(appID.isEmpty)
            }
        }
    }
}

// MARK: - 文字输入（TCL：直接注入到电视当前输入框）

struct TextInputSection: View {
    @EnvironmentObject var controller: RemoteController
    @State private var text = ""
    @State private var hint: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("文字输入", systemImage: "keyboard")
                .font(.subheadline.bold())

            Text("先在电视上打开搜索页、点一下输入框让它有光标，再回到这里打字发送。电视键盘太难用的时候走这条路。")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .bottom, spacing: 8) {
                TextField("输入要发到电视的文字", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)

                Button {
                    send(confirm: false)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                }
                .disabled(trimmed.isEmpty)
            }

            HStack(spacing: 8) {
                Button {
                    send(confirm: false)
                } label: {
                    Label("只发文字", systemImage: "text.cursor")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    send(confirm: true)
                } label: {
                    Label("发送并搜索", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .disabled(trimmed.isEmpty)

            if let hint = hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundColor(hint.contains("失败") ? .red : .secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send(confirm: Bool) {
        let value = trimmed
        guard !value.isEmpty else { return }
        guard controller.sendText(value) else {
            hint = "发送失败：连接已断开或正在重连"
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        focused = false
        if confirm {
            hint = "已发送，正在触发搜索…"
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                controller.sendConfirm()
            }
        } else {
            hint = "已发送 \(value.count) 字"
        }
    }
}

// MARK: - 普通按键

struct KeyButton: View {
    let icon: String
    let label: String
    let keyCode: Int
    let action: (Int) -> Void

    var body: some View {
        Button {
            action(keyCode)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                Text(label)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - 长按重复按键（方向 / 音量 / 频道）

struct RepeatKeyButton: View {
    let icon: String
    var label: String? = nil
    let keyCode: Int
    let action: (Int) -> Void
    @State private var timer: Timer?

    init(icon: String, label: String? = nil, keyCode: Int, action: @escaping (Int) -> Void) {
        self.icon = icon
        self.label = label
        self.keyCode = keyCode
        self.action = action
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
            if let label = label {
                Text(label)
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in start() }
                .onEnded { _ in stop() }
        )
    }

    private func start() {
        guard timer == nil else { return }
        action(keyCode)
        let t = Timer(timeInterval: 0.25, repeats: true) { _ in
            action(keyCode)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - 按压缩放效果

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
