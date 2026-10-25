import Foundation

enum ArchiveError: LocalizedError {
    case noFiles
    case missingFile(String)
    case zipFailed(String)

    var errorDescription: String? {
        switch self {
        case .noFiles:
            "没有可压缩的文件"
        case .missingFile(let name):
            "文件已不存在：\(name)"
        case .zipFailed(let message):
            message.isEmpty ? "ZIP 压缩失败" : "ZIP 压缩失败：\(message)"
        }
    }
}

struct ArchiveService: Sendable {
    func createArchive(files: [URL], destination: URL) async throws {
        guard !files.isEmpty else { throw ArchiveError.noFiles }
        for file in files {
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw ArchiveError.missingFile(file.lastPathComponent)
            }
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            for start in stride(from: 0, to: files.count, by: 100) {
                let chunk = Array(files[start..<min(start + 100, files.count)])
                try await runZip(arguments: ["-j", "-q", destination.path] + chunk.map(\.path))
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private func runZip(arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errors

            process.terminationHandler = { finishedProcess in
                let data = errors.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if finishedProcess.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ArchiveError.zipFailed(message))
                }
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
