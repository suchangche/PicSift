import AppKit
import SwiftUI

struct ImageViewerView: View {
    @ObservedObject var store: AppStore
    @StateObject private var zoomController = ZoomController()
    @StateObject private var loadingState = ImageLoadingState()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                ZoomableImageView(image: loadingState.image, controller: zoomController)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 82)

                if loadingState.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                        Text("正在载入原图…")
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .transition(.opacity)
                } else if loadingState.failed {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                        Text("无法显示这张图片")
                        Text(store.currentViewerItem?.url.lastPathComponent ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.white)
                    .transition(.opacity)
                }

                HStack {
                    sideNavigationZone(previous: true)
                    Spacer()
                    sideNavigationZone(previous: false)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 20)
                .padding(.top, 82)

                VStack {
                    topBar
                    Spacer()
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.16), value: loadingState.isLoading)

            bottomPanel
        }
        .background(Color.black.ignoresSafeArea())
        .background {
            Group {
                Button("") { store.showPreviousViewerItem() }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { store.showNextViewerItem() }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { zoomController.zoomIn() }
                    .keyboardShortcut("+", modifiers: [])
                Button("") { zoomController.zoomOut() }
                    .keyboardShortcut("-", modifiers: [])
                Button("") { zoomController.fit() }
                    .keyboardShortcut("0", modifiers: [])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .environment(\.colorScheme, .dark)
        .task(id: store.viewerItemID) {
            await loadCurrentImage()
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                store.closeViewer()
            } label: {
                Label("返回图库", systemImage: "chevron.left")
                    .font(.headline)
                    .frame(width: 116, height: 42)
                    .viewerControlBackground()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .help("返回图片列表 (Esc)")

            VStack(alignment: .leading, spacing: 2) {
                Text(store.currentViewerItem?.url.lastPathComponent ?? "")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let position = store.viewerPosition {
                    Text("\(position + 1) / \(store.filteredItems.count)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            Spacer()
            Button(role: .destructive) {
                store.requestDeleteCurrent()
            } label: {
                Image(systemName: "trash")
                    .font(.title3)
                    .frame(width: 44, height: 42)
                    .viewerControlBackground()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(store.currentViewerItem == nil || store.isDeleting || store.isArchiving || store.isCopying)
            .help("删除当前图片")
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func sideNavigationZone(previous: Bool) -> some View {
        let isEnabled = previous
            ? (store.viewerPosition ?? 0) > 0
            : (store.viewerPosition ?? 0) < store.filteredItems.count - 1
        return Button {
            if previous {
                store.showPreviousViewerItem()
            } else {
                store.showNextViewerItem()
            }
        } label: {
            ZStack {
                Rectangle().fill(.white.opacity(0.001))
                Image(systemName: previous ? "chevron.left" : "chevron.right")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(isEnabled ? 0.42 : 0.12))
                    .frame(width: 48, height: 64)
                    .viewerControlBackground(cornerRadius: 12)
            }
            .frame(width: 88)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(previous ? "上一张" : "下一张")
        .accessibilityLabel(previous ? "上一张" : "下一张")
    }

    private var bottomPanel: some View {
        HStack(spacing: 10) {
            ForEach(filmstripEntries) { entry in
                if let item = entry.item, let position = entry.position {
                    FilmstripThumbnail(
                        item: item,
                        position: position,
                        isSelected: item.id == store.viewerItemID
                    ) {
                        store.displayInViewer(item)
                    }
                } else {
                    Color.clear
                        .frame(width: 108, height: 74)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 74)
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().overlay(.white.opacity(0.12))
        }
    }

    private var filmstripEntries: [FilmstripEntry] {
        let visible = store.filteredItems
        guard let currentPosition = store.viewerPosition, !visible.isEmpty else { return [] }
        return (0...6).map { slot in
            let index = currentPosition + slot - 3
            let isValid = visible.indices.contains(index)
            return FilmstripEntry(
                id: slot,
                item: isValid ? visible[index] : nil,
                position: isValid ? index + 1 : nil
            )
        }
    }

    private func loadCurrentImage() async {
        guard let item = store.currentViewerItem else {
            loadingState.image = nil
            loadingState.isLoading = false
            loadingState.failed = false
            return
        }

        if let cachedImage = await FullImageCache.shared.cachedImage(for: item) {
            loadingState.image = cachedImage
            loadingState.isLoading = false
            loadingState.failed = false
            await FullImageCache.shared.preload(items: neighborItems(for: item))
            return
        }

        loadingState.failed = false
        loadingState.isLoading = false
        async let fullImage = FullImageCache.shared.image(for: item)
        let preview = await ThumbnailLoader.shared.thumbnail(for: item, maxPixelSize: 1200)
        guard !Task.isCancelled, store.viewerItemID == item.id else { return }

        if let preview {
            loadingState.image = preview
            loadingState.failed = false
        } else {
            loadingState.image = nil
            loadingState.isLoading = true
        }
        await FullImageCache.shared.preload(items: neighborItems(for: item))

        let loadedImage = await fullImage
        guard !Task.isCancelled, store.viewerItemID == item.id else { return }
        if let loadedImage {
            loadingState.image = loadedImage
            loadingState.failed = false
        } else if preview == nil {
            loadingState.image = nil
            loadingState.failed = true
        }
        loadingState.isLoading = false
    }

    private func neighborItems(for item: ImageItem) -> [ImageItem] {
        let visible = store.filteredItems
        guard let position = store.viewerPosition else { return [] }
        return [position - 2, position - 1, position + 1, position + 2]
            .filter { visible.indices.contains($0) }
            .map { visible[$0] }
    }
}

private struct FilmstripEntry: Identifiable {
    let id: Int
    let item: ImageItem?
    let position: Int?
}

private struct FilmstripThumbnail: View {
    let item: ImageItem
    let position: Int
    let isSelected: Bool
    let action: () -> Void

    @StateObject private var loadingState = ImageLoadingState()

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.white.opacity(0.08)
                if let image = loadingState.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity)
                } else if loadingState.failed {
                    Image(systemName: "photo")
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
            .frame(width: 108, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.16), lineWidth: 1)
            }
            .overlay(alignment: .bottomTrailing) {
                Text("\(position)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 4))
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
        .opacity(isSelected ? 1 : 0.66)
        .shadow(
            color: .black.opacity(isSelected ? 0.32 : 0.16),
            radius: isSelected ? 6 : 3,
            y: isSelected ? 3 : 2
        )
        .scaleEffect(isSelected ? 1.02 : 1)
        .offset(y: isSelected ? -2 : 0)
        .zIndex(isSelected ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .animation(.easeOut(duration: 0.18), value: loadingState.image != nil)
        .help(item.url.lastPathComponent)
        .task(id: item.id) {
            loadingState.failed = false
            loadingState.image = nil
            loadingState.image = await ThumbnailLoader.shared.thumbnail(for: item, maxPixelSize: 240)
            loadingState.failed = loadingState.image == nil
        }
    }
}
