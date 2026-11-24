//
//  RemotePadView.swift
//  TVRemote
//
//  遥控器界面：按用户自定义布局渲染按键网格
//

import SwiftUI
import UIKit

struct RemotePadView: View {
    @EnvironmentObject var controller: RemoteController
    @EnvironmentObject var store: PadLayoutStore

    @State private var text = ""
    @State private var appID = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                keyGrid

                if controller.isTCL {
                    TextInputSection()
                } else {
                    inputSection
                    appSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .onAppear { Haptics.prepare() }
    }

    // MARK: 按键网格

    private var visibleKeys: [PadKey] {
        store.layout.keys.filter { !(controller.isTCL && $0.googleOnly) }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10),
              count: store.layout.safeColumns)
    }

    @ViewBuilder
    private var keyGrid: some View {
        if visibleKeys.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 30))
                    .foregroundColor(.secondary)
                Text("布局里还没有按键")
                    .font(.subheadline)
                Text("点右上角的排版按钮添加")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(visibleKeys) { key in
                    PadKeyButton(key: key, showTitle: store.layout.showTitles) { code in
                        controller.sendKey(code)
                    }
                }
            }
        }
    }

    // MARK: 文字输入（Google TV）

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

    // MARK: 打开应用（Google TV）

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

// MARK: - 自定义按键按钮

struct PadKeyButton: View {
    let key: PadKey
    var showTitle: Bool = true
    let action: (Int) -> Void

    @State private var timer: Timer?

    var body: some View {
        Group {
            if key.holdRepeat {
                labelView
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onLongPressGesture(minimumDuration: 0.01,
                                        maximumDistance: 24,
                                        pressing: { isPressing in
                                            if isPressing { start() } else { stop() }
                                        },
                                        perform: {})
            } else {
                Button {
                    action(key.keyCode)
                } label: {
                    labelView
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
    }

    private var labelView: some View {
        VStack(spacing: 4) {
            if key.icon.isEmpty {
                Text(key.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Image(systemName: key.icon)
                    .font(.system(size: 21, weight: .medium))
                if showTitle {
                    Text(key.title)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .foregroundColor(KeyPalette.foreground(key.style))
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(KeyPalette.background(key.style))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(key.style == .ghost ? Color.secondary.opacity(0.35) : Color.clear,
                              lineWidth: 1.2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func start() {
        guard timer == nil else { return }
        action(key.keyCode)
        let t = Timer(timeInterval: 0.25, repeats: true) { _ in
            action(key.keyCode)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
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
        Haptics.success()
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

// MARK: - 按压缩放效果

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
