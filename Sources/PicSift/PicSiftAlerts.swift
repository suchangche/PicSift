import SwiftUI

private enum RoutedAlert: Identifiable {
    case deletion(PendingDeletion)
    case archive(ArchiveResult)
    case copy(CopyResult)
    case error(PresentedError)

    var id: UUID {
        switch self {
        case .deletion(let value): value.id
        case .archive(let value): value.id
        case .copy(let value): value.id
        case .error(let value): value.id
        }
    }
}

struct PicSiftAlerts: ViewModifier {
    @ObservedObject var store: AppStore
    let inViewer: Bool

    private var routedAlert: Binding<RoutedAlert?> {
        Binding<RoutedAlert?>(
            get: {
                if inViewer {
                    if let pending = store.pendingDeletion, pending.source == .viewer {
                        return .deletion(pending)
                    }
                    if let error = store.presentedError, error.origin == .viewer {
                        return .error(error)
                    }
                    return nil
                }

                if let pending = store.pendingDeletion, pending.source == .selection {
                    return .deletion(pending)
                }
                if let error = store.presentedError, error.origin == .gallery {
                    return .error(error)
                }
                if let result = store.archiveResult, result.origin == .gallery {
                    return .archive(result)
                }
                if let result = store.copyResult, result.origin == .gallery {
                    return .copy(result)
                }
                return nil
            },
            set: { newValue in
                guard newValue == nil else { return }
                if inViewer {
                    if store.pendingDeletion?.source == .viewer { store.pendingDeletion = nil }
                    if store.presentedError?.origin == .viewer { store.presentedError = nil }
                } else {
                    if store.pendingDeletion?.source == .selection { store.pendingDeletion = nil }
                    if store.presentedError?.origin == .gallery { store.presentedError = nil }
                    store.archiveResult = nil
                    store.copyResult = nil
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content.alert(item: routedAlert) { alert in
            switch alert {
            case .deletion(let pending):
                Alert(
                    title: Text(pending.title),
                    message: Text("图片将移到 macOS 废纸篓。本次启动期间可按 ⌘Z 撤回删除。"),
                    primaryButton: .destructive(Text("移到废纸篓")) {
                        store.pendingDeletion = nil
                        let origin: AlertOrigin = pending.source == .viewer ? .viewer : .gallery
                        Task { await store.delete(items: pending.items, origin: origin) }
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case .archive(let result):
                Alert(
                    title: Text("压缩完成"),
                    message: Text("已将 \(result.fileCount) 张图片压缩到：\n\(result.url.path)\n\n要在 Finder 中打开吗？"),
                    primaryButton: .default(Text("打开 Finder")) {
                        store.archiveResult = nil
                        store.revealArchive(at: result.url)
                    },
                    secondaryButton: .cancel(Text("完成"))
                )
            case .copy(let result):
                Alert(
                    title: Text("复制完成"),
                    message: Text("已将 \(result.fileCount) 张图片复制到：\n\(result.directory.path)\n\n要在 Finder 中打开吗？"),
                    primaryButton: .default(Text("打开 Finder")) {
                        store.copyResult = nil
                        store.revealCopiedFiles(at: result.urls)
                    },
                    secondaryButton: .cancel(Text("完成"))
                )
            case .error(let error):
                Alert(
                    title: Text(error.title),
                    message: Text(error.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }
}
