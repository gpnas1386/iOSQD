//
//  PadLayout.swift
//  TVRemote
//
//  可自定义的遥控按键布局：数据模型、按键库、持久化
//

import SwiftUI
import UIKit

// MARK: - 配色

enum KeyPalette {
    static func foreground(_ style: PadKeyStyle) -> Color {
        switch style {
        case .normal, .ghost: return .primary
        case .primary, .danger: return .white
        }
    }

    static func background(_ style: PadKeyStyle) -> Color {
        switch style {
        case .normal: return Color(.secondarySystemBackground)
        case .primary: return .accentColor
        case .danger: return Color.red.opacity(0.88)
        case .ghost: return .clear
        }
    }
}

// MARK: - 按键外观

enum PadKeyStyle: String, Codable, CaseIterable, Identifiable {
    case normal
    case primary
    case danger
    case ghost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "普通"
        case .primary: return "强调"
        case .danger: return "危险"
        case .ghost: return "描边"
        }
    }
}

// MARK: - 单个按键

struct PadKey: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var keyCode: Int
    var title: String
    /// 空字符串表示只显示文字（例如 OK 键）
    var icon: String
    /// 长按连发（方向 / 音量 / 频道）
    var holdRepeat: Bool = false
    var style: PadKeyStyle = .normal
    /// 只有 Android TV / Google TV 协议支持，TCL 映射表里没有这些键
    var googleOnly: Bool = false
}

// MARK: - 界面风格

enum PadStyle: String, Codable, CaseIterable, Identifiable {
    /// Apple TV 遥控器风格：一个大圆盘 + 一排常用键
    case siri
    /// 自由网格：每个按键都能自己排
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .siri: return "圆盘"
        case .grid: return "网格"
        }
    }

    var subtitle: String {
        switch self {
        case .siri: return "Apple TV 风格：大圆盘 + 一排常用键，主界面最干净"
        case .grid: return "自由网格：每个按键都能自己排、自己换图标"
        }
    }
}

// MARK: - 一套布局

struct PadLayout: Codable, Equatable {
    var columns: Int
    var showTitles: Bool
    var keys: [PadKey]
    var style: PadStyle

    init(columns: Int = 4,
         showTitles: Bool = true,
         keys: [PadKey] = [],
         style: PadStyle = .siri) {
        self.columns = columns
        self.showTitles = showTitles
        self.keys = keys
        self.style = style
    }

    enum CodingKeys: String, CodingKey {
        case columns, showTitles, keys, style
    }

    /// 手写解码，保证旧版本存下的布局（没有 style 字段）不会整个失效
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        columns = try container.decodeIfPresent(Int.self, forKey: .columns) ?? 4
        showTitles = try container.decodeIfPresent(Bool.self, forKey: .showTitles) ?? true
        keys = try container.decodeIfPresent([PadKey].self, forKey: .keys) ?? []
        style = try container.decodeIfPresent(PadStyle.self, forKey: .style) ?? .siri
    }

    var safeColumns: Int { min(max(columns, 3), 5) }
}

// MARK: - 预设

extension PadLayout {

    /// 默认：常用 14 键，TCL 下开箱即用
    static func defaultLayout() -> PadLayout {
        var keys: [PadKey] = []
        func add(_ code: Int, _ title: String, _ icon: String,
                 repeatable: Bool = false, style: PadKeyStyle = .normal) {
            keys.append(PadKey(keyCode: code, title: title, icon: icon,
                               holdRepeat: repeatable, style: style))
        }
        add(26, "电源", "power", style: .danger)
        add(4, "返回", "arrow.uturn.backward")
        add(3, "主页", "house.fill")
        add(82, "菜单", "line.3.horizontal")

        add(25, "音量−", "speaker.minus.fill", repeatable: true)
        add(19, "上", "chevron.up", repeatable: true)
        add(23, "OK", "", style: .primary)
        add(24, "音量+", "speaker.plus.fill", repeatable: true)

        add(164, "静音", "speaker.slash.fill")
        add(21, "左", "chevron.left", repeatable: true)
        add(20, "下", "chevron.down", repeatable: true)
        add(22, "右", "chevron.right", repeatable: true)

        add(167, "频道−", "chevron.down.circle", repeatable: true)
        add(166, "频道+", "chevron.up.circle", repeatable: true)

        return PadLayout(columns: 4, showTitles: true, keys: keys, style: .siri)
    }

    /// 精简：只留最常用的 9 个键
    static func compactLayout() -> PadLayout {
        var keys: [PadKey] = []
        func add(_ code: Int, _ title: String, _ icon: String,
                 repeatable: Bool = false, style: PadKeyStyle = .normal) {
            keys.append(PadKey(keyCode: code, title: title, icon: icon,
                               holdRepeat: repeatable, style: style))
        }
        add(26, "电源", "power", style: .danger)
        add(4, "返回", "arrow.uturn.backward")
        add(3, "主页", "house.fill")
        add(20, "下", "chevron.down", repeatable: true)

        add(25, "音量−", "speaker.minus.fill", repeatable: true)
        add(19, "上", "chevron.up", repeatable: true)
        add(23, "OK", "", style: .primary)
        add(24, "音量+", "speaker.plus.fill", repeatable: true)

        add(164, "静音", "speaker.slash.fill")

        return PadLayout(columns: 4, showTitles: true, keys: keys, style: .siri)
    }

    /// 全功能：默认布局 + 媒体 + 数字 + 设置（Google 专用键在 TCL 下自动隐藏）
    static func fullLayout() -> PadLayout {
        var layout = defaultLayout()

        layout.keys.append(PadKey(keyCode: 84, title: "搜索", icon: "magnifyingglass", googleOnly: true))
        layout.keys.append(PadKey(keyCode: 176, title: "设置", icon: "gearshape.fill", googleOnly: true))
        layout.keys.append(PadKey(keyCode: 178, title: "输入源", icon: "rectangle.connected.to.line.below", googleOnly: true))
        layout.keys.append(PadKey(keyCode: 219, title: "语音", icon: "mic.fill", googleOnly: true))

        layout.keys.append(PadKey(keyCode: 89, title: "快退", icon: "backward.fill", googleOnly: true))
        layout.keys.append(PadKey(keyCode: 88, title: "上一个", icon: "backward.end.fill", googleOnly: true))
        layout.keys.append(PadKey(keyCode: 85, title: "播放", icon: "playpause.fill", googleOnly: true))
        layout.keys.append(PadKey(keyCode: 87, title: "下一个", icon: "forward.end.fill", googleOnly: true))
        layout.keys.append(PadKey(keyCode: 90, title: "快进", icon: "forward.fill", googleOnly: true))

        let digits: [(String, Int)] = [
            ("1", 8), ("2", 9), ("3", 10),
            ("4", 11), ("5", 12), ("6", 13),
            ("7", 14), ("8", 15), ("9", 16),
            ("0", 7)
        ]
        for (title, code) in digits {
            layout.keys.append(PadKey(keyCode: code, title: title,
                                      icon: "\(title).square", googleOnly: true))
        }
        return layout
    }
}

// MARK: - 按键库

struct KeyCatalogItem: Identifiable {
    let keyCode: Int
    let title: String
    let icon: String
    var holdRepeat: Bool = false
    var googleOnly: Bool = false
    let group: String

    var id: String { "\(group)-\(keyCode)-\(title)" }

    var padKey: PadKey {
        PadKey(keyCode: keyCode, title: title, icon: icon,
               holdRepeat: holdRepeat, style: .normal, googleOnly: googleOnly)
    }
}

enum KeyCatalog {
    static let groups = ["方向", "系统", "音量 / 频道", "媒体播放", "数字"]

    private static func k(_ code: Int, _ title: String, _ icon: String, _ group: String,
                          repeat r: Bool = false, google g: Bool = false) -> KeyCatalogItem {
        KeyCatalogItem(keyCode: code, title: title, icon: icon,
                       holdRepeat: r, googleOnly: g, group: group)
    }

    static let items: [KeyCatalogItem] = [
        // 方向
        k(19, "上", "chevron.up", "方向", repeat: true),
        k(20, "下", "chevron.down", "方向", repeat: true),
        k(21, "左", "chevron.left", "方向", repeat: true),
        k(22, "右", "chevron.right", "方向", repeat: true),
        k(23, "OK", "circle.circle", "方向"),
        k(23, "确定", "", "方向"),

        // 系统
        k(26, "电源", "power", "系统"),
        k(4, "返回", "arrow.uturn.backward", "系统"),
        k(3, "主页", "house.fill", "系统"),
        k(82, "菜单", "line.3.horizontal", "系统"),
        k(84, "搜索", "magnifyingglass", "系统", google: true),
        k(176, "设置", "gearshape.fill", "系统", google: true),
        k(178, "输入源", "rectangle.connected.to.line.below", "系统", google: true),
        k(219, "语音", "mic.fill", "系统", google: true),
        k(165, "信息", "info.circle", "系统", google: true),
        k(172, "节目指南", "list.bullet", "系统", google: true),

        // 音量 / 频道
        k(24, "音量+", "speaker.plus.fill", "音量 / 频道", repeat: true),
        k(25, "音量−", "speaker.minus.fill", "音量 / 频道", repeat: true),
        k(164, "静音", "speaker.slash.fill", "音量 / 频道"),
        k(166, "频道+", "chevron.up.circle", "音量 / 频道", repeat: true),
        k(167, "频道−", "chevron.down.circle", "音量 / 频道", repeat: true),

        // 媒体播放（仅 Google TV）
        k(85, "播放/暂停", "playpause.fill", "媒体播放", google: true),
        k(86, "停止", "stop.fill", "媒体播放", google: true),
        k(87, "下一个", "forward.end.fill", "媒体播放", google: true),
        k(88, "上一个", "backward.end.fill", "媒体播放", google: true),
        k(89, "快退", "backward.fill", "媒体播放", google: true),
        k(90, "快进", "forward.fill", "媒体播放", google: true),
        k(85, "播放", "play.fill", "媒体播放", google: true),

        // 数字（仅 Google TV）
        k(8, "1", "1.square", "数字", google: true),
        k(9, "2", "2.square", "数字", google: true),
        k(10, "3", "3.square", "数字", google: true),
        k(11, "4", "4.square", "数字", google: true),
        k(12, "5", "5.square", "数字", google: true),
        k(13, "6", "6.square", "数字", google: true),
        k(14, "7", "7.square", "数字", google: true),
        k(15, "8", "8.square", "数字", google: true),
        k(16, "9", "9.square", "数字", google: true),
        k(7, "0", "0.square", "数字", google: true)
    ]

    static func items(in group: String) -> [KeyCatalogItem] {
        items.filter { $0.group == group }
    }
}

// MARK: - 可选图标

enum IconLibrary {
    static let symbols: [String] = [
        "power", "chevron.up", "chevron.down", "chevron.left", "chevron.right",
        "arrow.up", "arrow.down", "arrow.left", "arrow.right",
        "arrow.uturn.backward", "arrow.uturn.forward", "arrow.clockwise", "arrow.counterclockwise",
        "house.fill", "house", "line.3.horizontal", "line.3.horizontal.circle",
        "ellipsis", "ellipsis.circle", "square.grid.2x2.fill", "list.bullet",
        "speaker.fill", "speaker.plus.fill", "speaker.minus.fill",
        "speaker.slash.fill", "speaker.wave.2.fill", "speaker.wave.3.fill",
        "play.fill", "pause.fill", "playpause.fill", "stop.fill",
        "backward.fill", "forward.fill", "backward.end.fill", "forward.end.fill",
        "magnifyingglass", "gearshape.fill", "mic.fill", "mic",
        "tv", "tv.fill", "rectangle.on.rectangle", "rectangle.connected.to.line.below",
        "app.badge", "app.fill", "keyboard", "textformat", "character", "text.cursor",
        "number.square", "0.square", "1.square", "2.square", "3.square",
        "4.square", "5.square", "6.square", "7.square", "8.square", "9.square",
        "plus", "minus", "xmark", "checkmark", "circle.circle", "circle.fill",
        "chevron.up.circle", "chevron.down.circle", "arrow.up.circle", "arrow.down.circle",
        "info.circle", "questionmark.circle", "exclamationmark.triangle",
        "moon.fill", "sun.max.fill", "bell.fill", "bookmark.fill", "star.fill", "heart.fill",
        "gamecontroller.fill", "subtitles", "captions.bubble", "text.magnifyingglass",
        "hand.tap.fill", "cursorarrow", "circle.grid.3x3.fill", "dot.squareshape.fill"
    ]
}

// MARK: - 持久化

final class PadLayoutStore: ObservableObject {
    private static let storageKey = "tvremote.padlayout.v1"

    @Published var layout: PadLayout

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(PadLayout.self, from: data),
           !decoded.keys.isEmpty {
            layout = decoded
        } else {
            layout = .defaultLayout()
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func reset() {
        layout = .defaultLayout()
        save()
    }

    func apply(_ preset: PadLayout) {
        var value = preset
        value.style = layout.style     // 只换按键，不改变当前的界面风格
        layout = value
        save()
    }

    func append(_ key: PadKey) {
        layout.keys.append(key)
        save()
    }

    func remove(_ id: UUID) {
        layout.keys.removeAll { $0.id == id }
        save()
    }

    func update(_ key: PadKey) {
        guard let index = layout.keys.firstIndex(where: { $0.id == key.id }) else { return }
        layout.keys[index] = key
        save()
    }

    /// 把某个按键往前/往后挪一位（拖拽之外的备用排序方式）
    func move(_ id: UUID, offset: Int) {
        guard let index = layout.keys.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard target >= 0, target < layout.keys.count else { return }
        layout.keys.swapAt(index, target)
        save()
    }

    /// 拖拽重排：把 from 位置的按键移动到 to 位置
    func moveItem(from: Int, to: Int) {
        guard layout.keys.indices.contains(from), layout.keys.indices.contains(to) else { return }
        layout.keys.move(fromOffsets: IndexSet(integer: from),
                         toOffset: to > from ? to + 1 : to)
        save()
    }

    func setShowTitles(_ value: Bool) {
        layout.showTitles = value
        save()
    }

    func setStyle(_ value: PadStyle) {
        layout.style = value
        save()
    }

    func setColumns(_ value: Int) {
        layout.columns = min(max(value, 3), 5)
        save()
    }
}
