import Foundation

enum AlertOrigin {
    case gallery
    case viewer
}

enum ImageFormat: String, CaseIterable, Identifiable, Hashable, Sendable {
    case jpeg
    case raw
    case heic
    case png
    case gif
    case tiff
    case webP
    case bmp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .raw: "RAW"
        case .heic: "HEIC"
        case .png: "PNG"
        case .gif: "GIF"
        case .tiff: "TIFF"
        case .webP: "WebP"
        case .bmp: "BMP"
        }
    }

    static func fileType(for url: URL) -> ImageFormat? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "jpe", "jfif": .jpeg
        case "raw", "dng", "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2",
             "orf", "rw2", "raf", "pef", "srw", "erf", "3fr", "mef", "mos", "mrw",
             "x3f", "rwl", "iiq": .raw
        case "heic", "heif", "hif": .heic
        case "png": .png
        case "gif": .gif
        case "tif", "tiff": .tiff
        case "webp": .webP
        case "bmp", "dib": .bmp
        default: nil
        }
    }
}

struct ImageItem: Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL
    let format: ImageFormat
    let captureDate: Date
    let day: Date

    init(url: URL, format: ImageFormat, captureDate: Date, day: Date) {
        self.id = url.standardizedFileURL
        self.url = url.standardizedFileURL
        self.format = format
        self.captureDate = captureDate
        self.day = day
    }
}

struct DayOption: Identifiable, Hashable {
    let day: Date
    let count: Int

    var id: Date { day }
}

struct PendingDeletion: Identifiable {
    enum Source {
        case selection
        case viewer
    }

    let id = UUID()
    let items: [ImageItem]
    let source: Source

    var title: String {
        items.count == 1 ? "删除这张图片？" : "删除 \(items.count) 张图片？"
    }
}

struct ArchiveResult: Identifiable {
    let id = UUID()
    let url: URL
    let fileCount: Int
    let origin: AlertOrigin

    init(url: URL, fileCount: Int, origin: AlertOrigin = .gallery) {
        self.url = url
        self.fileCount = fileCount
        self.origin = origin
    }
}

struct CopyResult: Identifiable {
    let id = UUID()
    let urls: [URL]
    let directory: URL
    let origin: AlertOrigin

    var fileCount: Int { urls.count }

    init(urls: [URL], directory: URL, origin: AlertOrigin = .gallery) {
        self.urls = urls
        self.directory = directory
        self.origin = origin
    }
}
