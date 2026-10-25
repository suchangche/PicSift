import Foundation

struct FileOperationFailure: Sendable {
    let url: URL
    let message: String
}

struct TrashedItem: Sendable {
    let originalItem: ImageItem
    let trashedURL: URL
}

struct DeletionBatch: Identifiable, Sendable {
    let id: UUID
    let items: [TrashedItem]

    init(id: UUID = UUID(), items: [TrashedItem]) {
        self.id = id
        self.items = items
    }
}

struct TrashResult: Sendable {
    let batch: DeletionBatch?
    let failures: [FileOperationFailure]
}

struct RestoreResult: Sendable {
    let restoredItems: [ImageItem]
    let remainingBatch: DeletionBatch?
    let failures: [FileOperationFailure]
}

struct TrashService: Sendable {
    func trash(items: [ImageItem]) async -> TrashResult {
        await Task.detached(priority: .userInitiated) {
            var trashedItems: [TrashedItem] = []
            var failures: [FileOperationFailure] = []

            for item in items {
                do {
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: &resultingURL)
                    guard let trashedURL = resultingURL as URL? else {
                        failures.append(FileOperationFailure(url: item.url, message: "无法记录废纸篓中的位置"))
                        continue
                    }
                    trashedItems.append(TrashedItem(originalItem: item, trashedURL: trashedURL))
                } catch {
                    failures.append(FileOperationFailure(url: item.url, message: error.localizedDescription))
                }
            }

            return TrashResult(
                batch: trashedItems.isEmpty ? nil : DeletionBatch(items: trashedItems),
                failures: failures
            )
        }.value
    }

    func restore(batch: DeletionBatch) async -> RestoreResult {
        await Task.detached(priority: .userInitiated) {
            var restoredItems: [ImageItem] = []
            var remainingItems: [TrashedItem] = []
            var failures: [FileOperationFailure] = []

            for trashedItem in batch.items {
                let destination = trashedItem.originalItem.url
                do {
                    guard !FileManager.default.fileExists(atPath: destination.path) else {
                        throw CocoaError(.fileWriteFileExists)
                    }
                    try FileManager.default.moveItem(at: trashedItem.trashedURL, to: destination)
                    restoredItems.append(trashedItem.originalItem)
                } catch {
                    remainingItems.append(trashedItem)
                    failures.append(FileOperationFailure(url: destination, message: error.localizedDescription))
                }
            }

            return RestoreResult(
                restoredItems: restoredItems,
                remainingBatch: remainingItems.isEmpty ? nil : DeletionBatch(id: batch.id, items: remainingItems),
                failures: failures
            )
        }.value
    }
}

extension Array where Element == FileOperationFailure {
    var summary: String {
        let names = prefix(3).map { $0.url.lastPathComponent }.joined(separator: "、")
        let extra = count > 3 ? " 等 \(count) 个文件" : names
        let reason = first?.message ?? "未知错误"
        return "\(extra)\n\(reason)"
    }
}
