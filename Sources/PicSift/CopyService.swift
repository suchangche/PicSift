import Foundation

enum CopyError: LocalizedError {
    case noFiles

    var errorDescription: String? {
        "没有可复制的文件"
    }
}

struct CopyServiceResult: Sendable {
    let copiedURLs: [URL]
    let failures: [FileOperationFailure]
}

struct CopyService: Sendable {
    func copy(files: [URL], to directory: URL) async throws -> CopyServiceResult {
        guard !files.isEmpty else { throw CopyError.noFiles }
        return try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var copiedURLs: [URL] = []
            var failures: [FileOperationFailure] = []

            for source in files {
                try Task.checkCancellation()
                do {
                    guard FileManager.default.fileExists(atPath: source.path) else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    let destination = uniqueDestination(for: source, in: directory)
                    try FileManager.default.copyItem(at: source, to: destination)
                    copiedURLs.append(destination)
                } catch {
                    failures.append(FileOperationFailure(url: source, message: error.localizedDescription))
                }
            }
            return CopyServiceResult(copiedURLs: copiedURLs, failures: failures)
        }.value
    }

    private func uniqueDestination(for source: URL, in directory: URL) -> URL {
        let name = source.deletingPathExtension().lastPathComponent
        let pathExtension = source.pathExtension
        var index = 1
        var destination: URL
        repeat {
            let candidateName = index == 1 ? name : "\(name)-\(index)"
            destination = directory.appendingPathComponent(candidateName).appendingPathExtension(pathExtension)
            index += 1
        } while FileManager.default.fileExists(atPath: destination.path)
        return destination
    }
}
