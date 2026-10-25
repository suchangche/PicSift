import AppKit
import SwiftUI

struct GalleryView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider().opacity(0.45)
            content
            Divider().opacity(0.45)
            statusBar
        }
        .background {
            Button("") { store.requestDeleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
                .hidden()
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.filteredItems.count) 张图片")
                    .font(.headline)
                Text(store.visibleSelection.isEmpty ? "当前筛选结果" : "已选择 \(store.visibleSelection.count) 张")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(store.visibleSelection.isEmpty ? Color.secondary : Color.accentColor)
            }
            Spacer()
            if store.isArchiving || store.isCopying {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 2)
            } else if store.isRefiningDates {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("更新日期…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 2)
            }
            Button(store.visibleSelection.count == store.filteredItems.count && !store.filteredItems.isEmpty ? "取消全选" : "全选") {
                if store.visibleSelection.count == store.filteredItems.count {
                    store.clearSelection()
                } else {
                    store.selectAllFiltered()
                }
            }
            .buttonStyle(.bordered)
            .disabled(store.filteredItems.isEmpty)

            Button {
                Task { await store.copySelection() }
            } label: {
                Label("复制所选", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .disabled(store.visibleSelection.isEmpty || store.isCopying || store.isArchiving || store.isDeleting)

            Button {
                Task { await store.archiveSelection() }
            } label: {
                Label("压缩所选", systemImage: "archivebox")
            }
            .buttonStyle(.bordered)
            .disabled(store.visibleSelection.isEmpty || store.isCopying || store.isArchiving || store.isDeleting)

            Button(role: .destructive) {
                store.requestDeleteSelection()
            } label: {
                Label("删除", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(store.visibleSelection.isEmpty || store.isCopying || store.isDeleting || store.isArchiving)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(AppTheme.elevated)
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("正在读取图片和日期…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.items.isEmpty {
            ContentUnavailableView {
                Label("没有支持的图片", systemImage: "photo")
            } description: {
                Text("请选择包含 JPEG、RAW、HEIC、PNG 等图片的文件夹。")
            } actions: {
                Button("选择其他文件夹") { store.chooseFolder() }
                    .buttonStyle(.bordered)
            }
        } else if store.filteredItems.isEmpty {
            if store.selectedFormats.isEmpty && store.selectedDays.isEmpty {
                ContentUnavailableView {
                    Label("选择筛选条件", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("在左侧勾选图片格式或日期后开始显示。\n只选择一个分类时，另一个分类不限。")
                } actions: {
                    Button("显示全部图片") {
                        store.selectedFormats = Set(store.items.map(\.format))
                        store.selectedDays = Set(store.availableDays.map(\.day))
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ContentUnavailableView {
                    Label("没有符合筛选条件的图片", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("请调整图片格式或日期筛选。")
                } actions: {
                    Button("显示全部图片") {
                        store.selectedFormats = Set(store.items.map(\.format))
                        store.selectedDays = Set(store.availableDays.map(\.day))
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180), spacing: 18, alignment: .top)],
                    spacing: 20
                ) {
                    ForEach(store.filteredItems) { item in
                        ThumbnailCard(
                            item: item,
                            isSelected: store.selection.contains(item.id),
                            onSelect: { command, shift in
                                store.handleSelection(item, command: command, shift: shift)
                            },
                            onOpen: { store.openViewer(for: item) },
                            onDelete: {
                                if !store.selection.contains(item.id) {
                                    store.handleSelection(item, command: false, shift: false)
                                }
                                store.requestDeleteSelection()
                            }
                        )
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .animation(.easeInOut(duration: 0.18), value: store.selectedFormats)
                .animation(.easeInOut(duration: 0.18), value: store.selectedDays)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "archivebox")
                .foregroundStyle(.secondary)
            Button {
                store.chooseArchiveDirectory()
            } label: {
                Text("压缩包：\(store.archiveDirectory.lastPathComponent)")
                    .lineLimit(1)
            }
            .buttonStyle(.link)
            .help(store.archiveDirectory.path)

            Divider()
                .frame(height: 12)
                .opacity(0.35)

            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Button {
                store.chooseCopyDirectory()
            } label: {
                Text("复制到：\(store.copyDirectory.lastPathComponent)")
                    .lineLimit(1)
            }
            .buttonStyle(.link)
            .help(store.copyDirectory.path)

            Spacer()
            Text("单击选择 · ⌘多选 · ⇧范围选择 · 双击查看大图")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(AppTheme.elevated)
    }
}

private struct ThumbnailCard: View {
    let item: ImageItem
    let isSelected: Bool
    let onSelect: (Bool, Bool) -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void

    @StateObject private var loadingState = ImageLoadingState()
    @StateObject private var hover = HoverState()

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            AppTheme.subtleFill
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image = loadingState.image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity)
                    } else if loadingState.failed {
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                            Text("无法预览")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .overlay {
                    ThumbnailClickSurface(onSelect: onSelect, onOpen: onOpen)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay(alignment: .topLeading) {
                    Button {
                        onSelect(true, false)
                    } label: {
                        SelectionIndicator(isSelected: isSelected, highContrast: true, size: 22)
                            .padding(9)
                    }
                    .buttonStyle(.plain)
                    .help(isSelected ? "取消选择" : "选择")
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(
                    color: hover.isHovering ? .black.opacity(0.20) : .black.opacity(0.07),
                    radius: hover.isHovering ? 10 : 5,
                    y: hover.isHovering ? 5 : 3
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))

            Text(item.url.lastPathComponent)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                Text(item.format.displayName)
                Spacer()
                Text(item.captureDate, format: .dateTime.year().month().day())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hover.isHovering = $0 }
        .animation(.easeOut(duration: 0.16), value: hover.isHovering)
        .animation(.easeOut(duration: 0.16), value: isSelected)
        .animation(.easeOut(duration: 0.18), value: loadingState.image != nil)
        .zIndex(hover.isHovering ? 1 : 0)
        .contextMenu {
            Button("查看大图", action: onOpen)
            Divider()
            Button("删除图片…", role: .destructive, action: onDelete)
        }
        .task(id: item.id) {
            loadingState.failed = false
            loadingState.image = await ThumbnailLoader.shared.thumbnail(for: item)
            loadingState.failed = loadingState.image == nil
        }
    }
}
