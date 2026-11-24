//
//  SiriRemotePad.swift
//  TVRemote
//
//  Apple TV 遥控器风格：一个大圆盘 + 一排常用键 + 一条音量胶囊
//

import SwiftUI
import UIKit

struct SiriRemotePad: View {
    @EnvironmentObject var controller: RemoteController

    @State private var text = ""
    @State private var appID = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                topBar

                SiriTouchPad { code in
                    controller.sendKey(code)
                }
                .frame(maxWidth: 300)
                .padding(.vertical, 2)

                accessoryRow
                    .frame(maxWidth: 300)

                volumeBar
                    .frame(maxWidth: 300)

                if controller.isTCL {
                    TextInputSection()
                } else {
                    googleInputSection
                    googleLaunchSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .onAppear { Haptics.prepare() }
    }

    // MARK: 顶栏：状态 + 电源

    private var topBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button {
                controller.sendKey(26)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("电源")
        }
    }

    private var statusColor: Color {
        switch controller.linkState {
        case .online: return .green
        case .reconnecting: return .orange
        default: return .red
        }
    }

    private var statusText: String {
        switch controller.linkState {
        case .online: return "已连接"
        case .reconnecting: return "正在重连…"
        case .offline: return "已断开"
        default: return "未连接"
        }
    }

    // MARK: 圆盘下方三个键（返回 / 主页 / 菜单或播放）

    private var accessoryRow: some View {
        HStack(spacing: 10) {
            roundKey(icon: "chevron.backward", title: "返回", code: 4)
            roundKey(icon: "tv", title: "主页", code: 3)
            roundKey(icon: controller.isTCL ? "line.3.horizontal" : "playpause.fill",
                     title: controller.isTCL ? "菜单" : "播放",
                     code: controller.isTCL ? 82 : 85)
        }
    }

    private func roundKey(icon: String, title: String, code: Int) -> some View {
        Button {
            controller.sendKey(code)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: 音量胶囊

    private var volumeBar: some View {
        HStack(spacing: 0) {
            HoldRepeatButton(keyCode: 25, action: { controller.sendKey($0) }) {
                Image(systemName: "minus")
                    .font(.system(size: 18, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .contentShape(Rectangle())
            }

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 1, height: 22)

            Button {
                controller.sendKey(164)
            } label: {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 16))
                    .frame(width: 64, height: 54)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 1, height: 22)

            HoldRepeatButton(keyCode: 24, action: { controller.sendKey($0) }) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .contentShape(Rectangle())
            }
        }
        .foregroundColor(.primary)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
    }

    // MARK: Google TV 输入

    private var googleInputSection: some View {
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

    private var googleLaunchSection: some View {
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

// MARK: - 触控圆盘

struct SiriTouchPad: View {
    let onKey: (Int) -> Void

    @State private var driver = TouchRepeatDriver()
    @State private var activeDirection: Int?
    @State private var centerTouched = false
    @State private var hasTouched = false

    private static let centerRatio: CGFloat = 0.42
    private static let swipeThreshold: CGFloat = 16

    private enum Dir {
        case up, down, left, right

        var code: Int {
            switch self {
            case .up: return 19
            case .down: return 20
            case .left: return 21
            case .right: return 22
            }
        }

        var icon: String {
            switch self {
            case .up: return "chevron.up"
            case .down: return "chevron.down"
            case .left: return "chevron.left"
            case .right: return "chevron.right"
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2
            let center = CGPoint(x: side / 2, y: side / 2)

            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.09), radius: 14, x: 0, y: 7)

                VStack {
                    arrow(.up)
                    Spacer()
                    arrow(.down)
                }
                .padding(side * 0.11)

                HStack {
                    arrow(.left)
                    Spacer()
                    arrow(.right)
                }
                .padding(side * 0.11)

                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: side * 0.34, height: side * 0.34)
                    .overlay(
                        Circle().strokeBorder(
                            Color.accentColor.opacity(centerTouched ? 0.9 : 0.22),
                            lineWidth: centerTouched ? 2 : 1
                        )
                    )
                    .shadow(color: Color.black.opacity(0.07), radius: 5, x: 0, y: 2)
                    .overlay(
                        Text("OK")
                            .font(.system(size: side * 0.055, weight: .semibold))
                            .foregroundColor(centerTouched ? .accentColor : .secondary)
                    )
                    .scaleEffect(centerTouched ? 0.95 : 1)
                    .animation(.easeOut(duration: 0.12), value: centerTouched)
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleChanged(value, center: center, radius: radius)
                    }
                    .onEnded { value in
                        handleEnded(value)
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func arrow(_ dir: Dir) -> some View {
        let active = activeDirection == dir.code
        return Image(systemName: dir.icon)
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(active ? .accentColor : Color.primary.opacity(0.28))
            .scaleEffect(active ? 1.15 : 1)
            .animation(.easeOut(duration: 0.12), value: active)
            .frame(width: 46, height: 34)
    }

    // MARK: 手势

    private func handleChanged(_ value: DragGesture.Value, center: CGPoint, radius: CGFloat) {
        let dx = value.translation.width
        let dy = value.translation.height
        let distance = sqrt(dx * dx + dy * dy)

        // 第一次回调：判断手指落在中心还是边缘
        if !hasTouched {
            hasTouched = true
            let start = value.startLocation
            let ox = start.x - center.x
            let oy = start.y - center.y
            if sqrt(ox * ox + oy * oy) < radius * Self.centerRatio {
                centerTouched = true
            } else {
                activate(directionCode(dx: ox, dy: oy))
            }
        }

        // 滑动超过阈值：按滑动方向持续切换
        if distance > Self.swipeThreshold {
            let code = directionCode(dx: dx, dy: dy)
            if code != activeDirection {
                centerTouched = false
                activate(code)
            }
        }
    }

    private func handleEnded(_ value: DragGesture.Value) {
        driver.stop()
        if centerTouched {
            Haptics.key()
            onKey(23)
        }
        activeDirection = nil
        centerTouched = false
        hasTouched = false
    }

    private func directionCode(dx: CGFloat, dy: CGFloat) -> Int {
        if abs(dx) >= abs(dy) {
            return dx >= 0 ? 22 : 21
        } else {
            return dy >= 0 ? 20 : 19
        }
    }

    private func activate(_ code: Int) {
        activeDirection = code
        Haptics.key()
        onKey(code)
        driver.start(direction: code) { onKey($0) }
    }
}

// MARK: - 按住连发

private final class TouchRepeatDriver {
    private var timer: Timer?

    func start(direction: Int, action: @escaping (Int) -> Void) {
        stop()
        // 按住 0.4 秒后才开始连发，避免单击时多发
        let begin = Timer(timeInterval: 0.40, repeats: false) { _ in
            let repeatTimer = Timer(timeInterval: 0.11, repeats: true) { _ in
                action(direction)
            }
            RunLoop.main.add(repeatTimer, forMode: .common)
            self.timer = repeatTimer
        }
        RunLoop.main.add(begin, forMode: .common)
        timer = begin
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - 按住连发的按键（音量 ±）

struct HoldRepeatButton<Content: View>: View {
    let keyCode: Int
    let action: (Int) -> Void
    let content: () -> Content

    @State private var timer: Timer?
    @State private var pressed = false

    init(keyCode: Int,
         action: @escaping (Int) -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.keyCode = keyCode
        self.action = action
        self.content = content
    }

    var body: some View {
        content()
            .scaleEffect(pressed ? 0.94 : 1)
            .opacity(pressed ? 0.65 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.01,
                                maximumDistance: 60,
                                pressing: { isPressing in
                                    pressed = isPressing
                                    if isPressing { start() } else { stop() }
                                },
                                perform: {})
    }

    private func start() {
        guard timer == nil else { return }
        action(keyCode)
        let t = Timer(timeInterval: 0.12, repeats: true) { _ in
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
