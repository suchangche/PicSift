import Foundation
import ImageIO

enum ImageScanner {
    static func scan(folder: URL, calendar: Calendar = .current) async throws -> [ImageItem] {
        let items = try await scanStructure(folder: folder, calendar: calendar)
        return try await refineCaptureDates(items, calendar: calendar)
    }

    static func scanStructure(folder: URL, calendar: Calendar = .current) async throws -> [ImageItem] {
        try await Task.detached(priority: .userInitiated) {
            try scanStructureSynchronously(folder: folder, calendar: calendar)
        }.value
    }

    static func scanSynchronously(folder: URL, calendar: Calendar = .current) throws -> [ImageItem] {
        var items = try scanStructureSynchronously(folder: folder, calendar: calendar)
        let formatter = makeExifFormatter(calendar: calendar)
        for index in items.indices {
            try Task.checkCancellation()
            let item = items[index]
            let captureDate = exifCaptureDate(for: item.url, calendar: calendar, formatter: formatter) ?? item.captureDate
            items[index] = ImageItem(
                url: item.url,
                format: item.format,
                captureDate: captureDate,
                day: calendar.startOfDay(for: captureDate)
            )
        }
        return sort(items)
    }

    static func scanStructureSynchronously(folder: URL, calendar: Calendar = .current) throws -> [ImageItem] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .creationDateKey
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: []
        )

        var items: [ImageItem] = []
        items.reserveCapacity(urls.count)
        for url in urls {
            try Task.checkCancellation()
            guard let format = ImageFormat.fileType(for: url) else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let captureDate = values?.contentModificationDate ?? values?.creationDate ?? .distantPast
            items.append(ImageItem(
                url: url,
                format: format,
                captureDate: captureDate,
                day: calendar.startOfDay(for: captureDate)
            ))
        }
        return sort(items)
    }

    static func refineCaptureDates(_ items: [ImageItem], calendar: Calendar = .current) async throws -> [ImageItem] {
        guard !items.isEmpty else { return items }
        let indices = Array(items.indices)
        let chunks = stride(from: 0, to: indices.count, by: 8).map {
            Array(indices[$0..<min($0 + 8, indices.count)])
        }
        var refined = items
        var batchStart = 0

        while batchStart < chunks.count {
            let batch = chunks[batchStart..<min(batchStart + 4, chunks.count)]
            try await withThrowingTaskGroup(of: [(Int, ImageItem)].self) { group in
                for chunk in batch {
                    group.addTask {
                        let formatter = makeExifFormatter(calendar: calendar)
                        var changes: [(Int, ImageItem)] = []
                        for index in chunk {
                            try Task.checkCancellation()
                            let item = items[index]
                            let captureDate = exifCaptureDate(for: item.url, calendar: calendar, formatter: formatter) ?? item.captureDate
                            changes.append((index, ImageItem(
                                url: item.url,
                                format: item.format,
                                captureDate: captureDate,
                                day: calendar.startOfDay(for: captureDate)
                            )))
                        }
                        return changes
                    }
                }
                for try await changes in group {
                    for (index, item) in changes {
                        refined[index] = item
                    }
                }
            }
            batchStart += 4
        }
        return refined
    }

    static func sort(_ items: [ImageItem]) -> [ImageItem] {
        items.sorted { left, right in
            if left.captureDate != right.captureDate {
                return left.captureDate > right.captureDate
            }
            return left.url.lastPathComponent.localizedStandardCompare(right.url.lastPathComponent) == .orderedAscending
        }
    }

    private static func makeExifFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }

    private static func exifCaptureDate(for url: URL, calendar: Calendar, formatter: DateFormatter) -> Date? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any]
        else { return nil }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let candidates = [
            exif?[kCGImagePropertyExifDateTimeOriginal] as? String,
            exif?[kCGImagePropertyExifDateTimeDigitized] as? String,
            tiff?[kCGImagePropertyTIFFDateTime] as? String
        ]
        for value in candidates {
            guard let value, value.count >= 19 else { continue }
            if let date = formatter.date(from: String(value.prefix(19))) {
                return date
            }
        }
        return nil
    }
}
