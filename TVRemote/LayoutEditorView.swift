//
//  LayoutEditorView.swift
//  TVRemote
//
//  自定义按键布局：拖拽排序、换图标、改文字、增删按键
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 布局编辑器

struct LayoutEditorView: View {
    @EnvironmentObject var store: PadLayoutStore
    @EnvironmentObject var controller: RemoteController
    @Environment(\.dismiss) private var dismiss

    @State private var draggingID: UUID?
    @State private var editingKey: PadKey?
    @State private var showLibrary = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsCard
                    editorGrid
                    if store.layout.keys.isEmpty {
                        emptyHint
                    }
                    addButton
                    tipView
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("自定义布局")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button {
                            confirmReset = true
                        } label: {
                            Label("恢复默认布局", systemImage: "arrow.counterclockwise")
                        }
                        Button {
                            store.apply(.compactLayout())
                        } label: {
                            Label("精简布局", systemImage: "square.grid.3x3")
                        }
                        Button {
                            store.apply(.fullLayout())
                        } label: {
                            Label("全功能布局", systemImage: "square.grid.3x3.fill")
                        }
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(item: $editingKey) { key in
                KeyEditorView(key: key) { updated in
                    store.update(updated)
                } onDelete: {
                    store.remove(key.id)
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $showLibrary) {
                KeyLibraryView()
                    .environmentObject(store)
                    .environmentObject(controller)
            }
            .alert("恢复默认布局？", isPresented: $confirmReset) {
                Button("取消", role: .cancel) {}
                Button("恢复", role: .destructive) { store.reset() }
            } message: {
                Text("当前的自定义排版会被覆盖。")
            }
        }
    }

    // MARK: 设置卡片

    private var settingsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("每行按键数")
                    .font(.subheadline)
                Spacer()
                Picker("每行按键数", selection: columnsBinding) {
                    Text("3").tag(3)
                    Text("4").tag(4)
                    Text("5").tag(5)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            .padding(12)

            Divider().padding(.leading, 12)

            Toggle(isOn: showTitlesBinding) {
                Text("显示按键文字")
                    .font(.subheadline)
            }
            .padding(12)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var columnsBinding: Binding<Int> {
        Binding(
            get: { store.layout.safeColumns },
            set: { store.setColumns($0) }
        )
    }

    private var showTitlesBinding: Binding<Bool> {
        Binding(
            get: { store.layout.showTitles },
            set: { store.setShowTitles($0) }
        )
    }

    // MARK: 网格

    private var editorColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10),
              count: store.layout.safeColumns)
    }

    private var editorGrid: some View {
        LazyVGrid(columns: editorColumns, spacing: 10) {
            ForEach(store.layout.keys) { key in
                EditKeyCell(key: key, showTitle: store.layout.showTitles)
                    .onDrag {
                        draggingID = key.id
                        return NSItemProvider(object: key.id.uuidString as NSString)
                    }
                    .onDrop(of: [UTType.text],
                            delegate: KeyDropDelegate(item: key,
                                                      store: store,
                                                      dragging: $draggingID))
                    .onTapGesture { editingKey = key }
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 26))
                .foregroundColor(.secondary)
            Text("还没有按键，点下面从按键库添加")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var addButton: some View {
        Button {
            showLibrary = true
        } label: {
            Label("添加按键", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    private var tipView: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lightbulb")
                .font(.caption)
            Text("点一下按键可以换图标、改文字；长按按键拖动可以调整位置。改完点右上角「完成」保存，回到遥控页立即生效。")
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 4)
    }
}

// MARK: - 编辑态按键格

struct EditKeyCell: View {
    let key: PadKey
    let showTitle: Bool

    var body: some View {
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
                .strokeBorder(Color.accentColor.opacity(0.55),
                              style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - 拖拽重排

struct KeyDropDelegate: DropDelegate {
    let item: PadKey
    let store: PadLayoutStore
    @Binding var dragging: UUID?

    func dropEntered(info: DropInfo) {
        guard let dragging = dragging, dragging != item.id,
              let from = store.layout.keys.firstIndex(where: { $0.id == dragging }),
              let to = store.layout.keys.firstIndex(where: { $0.id == item.id }),
              from != to else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            store.moveItem(from: from, to: to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        Haptics.key()
        return true
    }
}

// MARK: - 按键库

struct KeyLibraryView: View {
    @EnvironmentObject var store: PadLayoutStore
    @Environment(\.dismiss) private var dismiss

    @State private var lastAdded: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(KeyCatalog.groups, id: \.self) { group in
                    Section {
                        ForEach(KeyCatalog.items(in: group)) { item in
                            Button {
                                add(item)
                            } label: {
                                row(item)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text(group)
                            if group == "媒体播放" || group == "数字" {
                                Text("仅 Android TV")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("添加按键")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func row(_ item: KeyCatalogItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon.isEmpty ? "circle.circle" : item.icon)
                .font(.system(size: 16))
                .frame(width: 26)
                .foregroundColor(.accentColor)
            Text(item.title)
            if item.holdRepeat {
                Text("长按连发")
                    .font(.system(size: 9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if lastAdded == item.id {
                Text("已添加")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
            Image(systemName: "plus.circle.fill")
                .foregroundColor(.accentColor)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private func add(_ item: KeyCatalogItem) {
        store.append(item.padKey)
        Haptics.key()
        lastAdded = item.id
    }
}

// MARK: - 单个按键编辑

struct KeyEditorView: View {
    @EnvironmentObject var store: PadLayoutStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PadKey

    private let onSave: (PadKey) -> Void
    private let onDelete: () -> Void

    init(key: PadKey,
         onSave: @escaping (PadKey) -> Void,
         onDelete: @escaping () -> Void) {
        _draft = State(initialValue: key)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    previewView
                    titleField
                    iconPicker
                    optionsCard
                    positionButtons
                    deleteButton
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("编辑按键")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: 预览

    private var previewView: some View {
        VStack(spacing: 8) {
            VStack(spacing: 5) {
                if draft.icon.isEmpty {
                    Text(draft.title.isEmpty ? "按键" : draft.title)
                        .font(.system(size: 21, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Image(systemName: draft.icon)
                        .font(.system(size: 26, weight: .medium))
                    Text(draft.title.isEmpty ? "按键" : draft.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
            }
            .foregroundColor(KeyPalette.foreground(draft.style))
            .frame(width: 104, height: 84)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(KeyPalette.background(draft.style))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(draft.style == .ghost ? Color.secondary.opacity(0.35) : Color.clear,
                                  lineWidth: 1.2)
            )

            Text("按键码 \(draft.keyCode)" + (draft.googleOnly ? " · 仅 Android TV" : ""))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: 文字

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("显示文字")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("例如：音量+", text: $draft.title)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
    }

    // MARK: 图标

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("图标")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("点「无」则只显示文字")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                      spacing: 8) {
                noIconCell
                ForEach(IconLibrary.symbols, id: \.self) { name in
                    iconCell(name)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var noIconCell: some View {
        Button {
            draft.icon = ""
        } label: {
            Text("无")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(draft.icon.isEmpty ? Color.accentColor.opacity(0.18)
                                                 : Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(draft.icon.isEmpty ? Color.accentColor : Color.clear,
                                      lineWidth: 1.5)
                )
                .foregroundColor(draft.icon.isEmpty ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func iconCell(_ name: String) -> some View {
        Button {
            draft.icon = name
        } label: {
            Image(systemName: name)
                .font(.system(size: 18))
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(draft.icon == name ? Color.accentColor.opacity(0.18)
                                                 : Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(draft.icon == name ? Color.accentColor : Color.clear,
                                      lineWidth: 1.5)
                )
                .foregroundColor(draft.icon == name ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: 选项

    private var optionsCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $draft.holdRepeat) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("长按连发")
                        .font(.subheadline)
                    Text("按住不放持续发送，适合方向、音量、频道")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)

            Divider().padding(.leading, 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("样式")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("样式", selection: $draft.style) {
                    ForEach(PadKeyStyle.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: 位置

    private var positionButtons: some View {
        HStack(spacing: 10) {
            Button {
                store.move(draft.id, offset: -1)
                dismiss()
            } label: {
                Label("前移", systemImage: "arrow.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canMove(-1))

            Button {
                store.move(draft.id, offset: 1)
                dismiss()
            } label: {
                Label("后移", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canMove(1))
        }
    }

    private func canMove(_ offset: Int) -> Bool {
        guard let index = store.layout.keys.firstIndex(where: { $0.id == draft.id }) else { return false }
        let target = index + offset
        return target >= 0 && target < store.layout.keys.count
    }

    // MARK: 删除

    private var deleteButton: some View {
        Button(role: .destructive) {
            onDelete()
            dismiss()
        } label: {
            Label("删除这个按键", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}
