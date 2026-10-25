import AppKit
import ImageIO

actor ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [NSString: Task<NSImage?, Never>] = [:]

    init() {
        cache.countLimit = 500
        cache.totalCostLimit = 160 * 1024 * 1024
    }

    func thumbnail(for item: ImageItem, maxPixelSize: Int = 480) async -> NSImage? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: item.url.path)
        let modification = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(item.url.path)|\(maxPixelSize)|\(modification)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task.detached(priority: .userInitiated) {
            ImageDecoder.thumbnail(for: item.url, maxPixelSize: maxPixelSize)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil

        if let image {
            let cost = image.representations.reduce(0) { $0 + $1.pixelsWide * $1.pixelsHigh * 4 }
            cache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }
}

enum ImageDecoder {
    static func thumbnail(for url: URL, maxPixelSize: Int) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return NSImage(contentsOf: url)
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return NSImage(contentsOf: url)
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    static func fullImage(for url: URL) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return NSImage(contentsOf: url) }

        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        if orientation == 1 {
            let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
                return NSImage(contentsOf: url)
            }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
