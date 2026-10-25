import AppKit
import Foundation

actor FullImageCache {
    static let shared = FullImageCache()

    private struct Key: Hashable {
        let path: String
        let modification: TimeInterval
    }

    private struct Entry {
        let image: NSImage
        let cost: Int
    }

    private final class LoadTask {
        let task: Task<NSImage?, Never>
        init(_ task: Task<NSImage?, Never>) {
            self.task = task
        }
    }

    private let costLimit: Int
    private let countLimit: Int

    private var entries: [Key: Entry] = [:]
    private var usageOrder: [Key] = []
    private var totalCost = 0
    private var inFlight: [Key: LoadTask] = [:]

    init(costLimit: Int = 768 * 1024 * 1024, countLimit: Int = 7) {
        self.costLimit = costLimit
        self.countLimit = countLimit
    }

    func cachedImage(for item: ImageItem) -> NSImage? {
        guard let key = makeKey(for: item), let entry = entries[key] else { return nil }
        touch(key)
        return entry.image
    }

    func image(for item: ImageItem) async -> NSImage? {
        guard let key = makeKey(for: item) else {
            return await Task.detached(priority: .userInitiated) {
                ImageDecoder.fullImage(for: item.url)
            }.value
        }

        if let entry = entries[key] {
            touch(key)
            return entry.image
        }
        if let existing = inFlight[key] {
            return await existing.task.value
        }

        let box = LoadTask(Task.detached(priority: .userInitiated) {
            ImageDecoder.fullImage(for: item.url)
        })
        inFlight[key] = box
        let image = await box.task.value
        finalize(box, forKey: key, image: image)
        return image
    }

    func preload(items: [ImageItem]) {
        for item in items {
            guard let key = makeKey(for: item) else { continue }
            guard entries[key] == nil, inFlight[key] == nil else { continue }

            let box = LoadTask(Task.detached(priority: .utility) {
                ImageDecoder.fullImage(for: item.url)
            })
            inFlight[key] = box
            Task { [weak self] in
                let image = await box.task.value
                await self?.finalize(box, forKey: key, image: image)
            }
        }
    }

    private func finalize(_ box: LoadTask, forKey key: Key, image: NSImage?) {
        guard inFlight[key] === box else { return }
        inFlight[key] = nil
        if let image {
            insert(Entry(image: image, cost: estimatedCost(of: image)), forKey: key)
        }
    }

    private func makeKey(for item: ImageItem) -> Key? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: item.url.path),
              let modification = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970
        else { return nil }
        return Key(path: item.url.path, modification: modification)
    }

    private func touch(_ key: Key) {
        if let index = usageOrder.firstIndex(of: key) {
            usageOrder.remove(at: index)
            usageOrder.append(key)
        }
    }

    private func insert(_ entry: Entry, forKey key: Key) {
        if let existing = entries[key] {
            totalCost -= existing.cost
            if let index = usageOrder.firstIndex(of: key) {
                usageOrder.remove(at: index)
            }
        }
        entries[key] = entry
        usageOrder.append(key)
        totalCost += entry.cost
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        while usageOrder.count > 1 {
            let overCount = usageOrder.count > countLimit
            let overCost = totalCost > costLimit
            guard overCount || overCost else { return }
            let oldestKey = usageOrder[0]
            usageOrder.removeFirst()
            if let oldest = entries[oldestKey] {
                entries[oldestKey] = nil
                totalCost -= oldest.cost
            }
        }
    }

    private nonisolated func estimatedCost(of image: NSImage) -> Int {
        image.representations.reduce(0) { $0 + $1.pixelsWide * $1.pixelsHigh * 4 }
    }
}
