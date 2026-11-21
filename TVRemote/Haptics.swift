//
//  Haptics.swift
//  TVRemote
//
//  触觉反馈封装。
//  - 统一在主线程调用（UIKit 的反馈引擎要求）
//  - 按键做了节流：长按方向键 / 音量键每 0.25 秒触发一次，避免震感过密
//  - 开关状态由 RemoteController 同步到 `enabled`
//

import UIKit

enum Haptics {
    /// 由设置项同步过来；关闭后所有反馈直接短路
    static var enabled = true

    /// 按键最小触发间隔（秒）。长按重复是 0.25s 一次，这里留一点余量
    private static let keyInterval: TimeInterval = 0.08
    private static var lastKeyTime = Date.distantPast

    private static var lightGenerator: UIImpactFeedbackGenerator?
    private static var notificationGenerator: UINotificationFeedbackGenerator?

    /// 预热引擎，减少第一次按键的延迟（在遥控页出现时调一次）
    static func prepare() {
        guard enabled else { return }
        if lightGenerator == nil {
            lightGenerator = UIImpactFeedbackGenerator(style: .light)
        }
        lightGenerator?.prepare()
        if notificationGenerator == nil {
            notificationGenerator = UINotificationFeedbackGenerator()
        }
        notificationGenerator?.prepare()
    }

    /// 普通遥控按键
    static func key() {
        guard enabled else { return }
        let now = Date()
        guard now.timeIntervalSince(lastKeyTime) >= keyInterval else { return }
        lastKeyTime = now

        if lightGenerator == nil {
            lightGenerator = UIImpactFeedbackGenerator(style: .light)
        }
        lightGenerator?.impactOccurred()
        lightGenerator?.prepare()
    }

    /// 连接成功 / 发送成功
    static func success() {
        guard enabled else { return }
        notify(.success)
    }

    /// 连接断开 / 发送失败
    static func warning() {
        guard enabled else { return }
        notify(.warning)
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        if notificationGenerator == nil {
            notificationGenerator = UINotificationFeedbackGenerator()
        }
        notificationGenerator?.notificationOccurred(type)
        notificationGenerator?.prepare()
    }
}
