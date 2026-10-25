import AppKit
import Foundation

struct PresentedError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let origin: AlertOrigin

    init(title: String, message: String, origin: AlertOrigin = .gallery) {
        self.title = title
        self.message = message
        self.origin = origin
    }
}

@MainActor
final class AppStore: ObservableObject {
    private enum SettingsKeys {
        static let archiveDirectoryPath = "archiveDirectoryPath"
        static let copyDirectoryPath = "copyDirectoryPath"
    }

    @Published private(set) var folderURL: URL?
    @Published private(set) var items: [ImageItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRefiningDates = false
    @Published private(set) var selection: Set<URL> = []
    @Published private(set) var viewerItemID: URL?
    @Published private(set) var isDeleting = false
    @Published private(set) var isArchiving = false
    @Published private(set) var isCopying = false
    @Published var isSidebarVisible = true

    @Published var selectedFormats: Set<ImageFormat> = [] {
        didSet { filtersChanged() }
    }
    @Published var selectedDays: Set<Date> = [] {
        didSet { filtersChanged() }
    }
    @Published var pendingDeletion: PendingDeletion?
    @Published var archiveResult: ArchiveResult?
    @Published var copyResult: CopyResult?
    @Published var presentedError: PresentedError?
    @Published var archiveDirectory: URL {
        didSet { userDefaults.set(archiveDirectory.path, forKey: SettingsKeys.archiveDirectoryPath) }
    }
    @Published var copyDirectory: URL {
        didSet { userDefaults.set(copyDirectory.path, forKey: SettingsKeys.copyDirectoryPath) }
    }

    private var undoStack: [DeletionBatch] = []
    private var selectionAnchor: URL?
    private var scanGeneration = 0
    private let trashService: TrashService
    private let archiveService: ArchiveService
    private let copyService: CopyService
    private let userDefaults: UserDefaults

    init(
        trashService: TrashService = TrashService(),
        archiveService: ArchiveService = ArchiveService(),
        copyService: CopyService = CopyService(),
        archiveDirectory: URL? = nil,
        copyDirectory: URL? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.trashService = trashService
        self.archiveService = archiveService
        self.copyService = copyService
        self.userDefaults = userDefaults
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        self.archiveDirectory = archiveDirectory
            ?? userDefaults.string(forKey: SettingsKeys.archiveDirectoryPath).map { URL(fileURLWithPath: $0) }
            ?? downloads
        self.copyDirectory = copyDirectory
            ?? userDefaults.string(forKey: SettingsKeys.copyDirectoryPath).map { URL(fileURLWithPath: $0) }
            ?? downloads.appendingPathComponent("PicSift Copies", isDirectory: true)
    }

    var filteredItems: [ImageItem] {
        guard !selectedFormats.isEmpty || !selectedDays.isEmpty else { return [] }
        return items.filter { item in
            let matchesFormat = selectedFormats.isEmpty || selectedFormats.contains(item.format)
            let matchesDay = selectedDays.isEmpty || selectedDays.contains(item.day)
            return matchesFormat && matchesDay
        }
    }

    var visibleSelection: [ImageItem] {
        filteredItems.filter { selection.contains($0.id) }
    }

    var availableDays: [DayOption] {
        var counts: [Date: Int] = [:]
        for item in items {
            counts[item.day, default: 0] += 1
        }
        return counts.map { DayOption(day: $0.key, count: $0.value) }
            .sorted { $0.day > $1.day }
    }

    var canUndo: Bool {
        !undoStack.isEmpty && !isDeleting && !isArchiving && !isCopying
    }

    var currentViewerItem: ImageItem? {
        guard let viewerItemID else { return nil }
        return filteredItems.first { $0.id == viewerItemID }
    }

    var viewerPosition: Int? {
        guard let viewerItemID else { return nil }
        return filteredItems.firstIndex { $0.id == viewerItemID }
    }

    func chooseFolder() {
        guard !isDeleting && !isCopying else { return }
        let panel = NSOpenPanel()
        panel.title = "选择图片文件夹"
        panel.message = "选择要浏览的文件夹（不包含子文件夹）"
        panel.prompt = "打开"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = folderURL
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.loadFolder(at: url)
            }
        }
    }

    func loadFolder(at url: URL) async {
        guard !isDeleting else { return }
        scanGeneration += 1
        let generation = scanGeneration
        closeViewer()
        undoStack.removeAll()
        pendingDeletion = nil
        folderURL = url.standardizedFileURL
        items = []
        selection = []
        selectedFormats = []
        selectedDays = []
        isLoading = true
        isRefiningDates = false

        do {
            let initialItems = try await ImageScanner.scanStructure(folder: url)
            guard generation == scanGeneration else { return }
            adoptScannedItems(initialItems, folder: url)
            isLoading = false
            isRefiningDates = true

            let refinedItems = try await ImageScanner.refineCaptureDates(initialItems)
            guard generation == scanGeneration else { return }
            applyRefinedItems(refinedItems)
            isRefiningDates = false
        } catch is CancellationError {
            if generation == scanGeneration {
                isLoading = false
                isRefiningDates = false
            }
        } catch {
            guard generation == scanGeneration else { return }
            isLoading = false
            isRefiningDates = false
            presentedError = PresentedError(
                title: items.isEmpty ? "无法打开文件夹" : "无法补全部分拍摄日期",
                message: error.localizedDescription
            )
        }
    }

    func adoptScannedItems(_ scannedItems: [ImageItem], folder: URL? = nil) {
        if let folder { folderURL = folder.standardizedFileURL }
        items = ImageScanner.sort(scannedItems)
        selectedFormats = items.contains { $0.format == .jpeg } ? [.jpeg] : []
        selectedDays = []
        selection = []
        selectionAnchor = nil
        isRefiningDates = false
    }

    func applyRefinedItems(_ refinedItems: [ImageItem]) {
        let currentIDs = Set(items.map(\.id))
        items = ImageScanner.sort(refinedItems.filter { currentIDs.contains($0.id) })
        selectedDays = selectedDays.intersection(Set(items.map(\.day)))
        filtersChanged()
    }

    func setFormat(_ format: ImageFormat, included: Bool) {
        if included {
            selectedFormats.insert(format)
        } else {
            selectedFormats.remove(format)
        }
    }

    func setDay(_ day: Date, included: Bool) {
        if included {
            selectedDays.insert(day)
        } else {
            selectedDays.remove(day)
        }
    }

    func handleSelection(_ item: ImageItem, command: Bool, shift: Bool) {
        let visible = filteredItems
        guard visible.contains(where: { $0.id == item.id }) else { return }

        if shift, let selectionAnchor,
           let anchorIndex = visible.firstIndex(where: { $0.id == selectionAnchor }),
           let itemIndex = visible.firstIndex(where: { $0.id == item.id }) {
            let range = min(anchorIndex, itemIndex)...max(anchorIndex, itemIndex)
            let rangeSelection = Set(visible[range].map(\.id))
            if command {
                selection.formUnion(rangeSelection)
            } else {
                selection = rangeSelection
            }
        } else if command {
            if selection.contains(item.id) {
                selection.remove(item.id)
            } else {
                selection.insert(item.id)
            }
            selectionAnchor = item.id
        } else if selection.contains(item.id) {
            selection.remove(item.id)
            if selectionAnchor == item.id {
                selectionAnchor = nil
            }
        } else {
            selection = [item.id]
            selectionAnchor = item.id
        }
    }

    func selectAllFiltered() {
        selection = Set(filteredItems.map(\.id))
    }

    func clearSelection() {
        selection = []
        selectionAnchor = nil
    }

    func requestDeleteSelection() {
        let targets = visibleSelection
        guard !targets.isEmpty, !isDeleting, !isArchiving && !isCopying, pendingDeletion == nil else { return }
        pendingDeletion = PendingDeletion(items: targets, source: .selection)
    }

    func requestDeleteCurrent() {
        guard let currentViewerItem, !isDeleting, !isArchiving && !isCopying, pendingDeletion == nil else { return }
        pendingDeletion = PendingDeletion(items: [currentViewerItem], source: .viewer)
    }

    func delete(items requestedItems: [ImageItem], origin: AlertOrigin = .gallery) async {
        guard !isDeleting, !isArchiving && !isCopying else { return }
        let allowed = Set(filteredItems.map(\.id))
        let targets = requestedItems.filter { allowed.contains($0.id) }
        guard !targets.isEmpty else { return }

        let previousVisible = filteredItems
        let previousViewerIndex = viewerItemID.flatMap { id in
            previousVisible.firstIndex { $0.id == id }
        }
        isDeleting = true
        defer { isDeleting = false }

        let result = await trashService.trash(items: targets)
        if let batch = result.batch {
            undoStack.append(batch)
            let deletedIDs = Set(batch.items.map { $0.originalItem.id })
            items.removeAll { deletedIDs.contains($0.id) }
            selection.subtract(deletedIDs)

            if let viewerItemID, deletedIDs.contains(viewerItemID) {
                let remaining = previousVisible.filter { !deletedIDs.contains($0.id) }
                if remaining.isEmpty {
                    closeViewer()
                } else {
                    let index = min(previousViewerIndex ?? 0, remaining.count - 1)
                    self.viewerItemID = remaining[index].id
                }
            }
        }

        if !result.failures.isEmpty {
            presentedError = PresentedError(
                title: "部分图片未能删除",
                message: result.failures.summary,
                origin: origin
            )
        }
    }

    func undoLastDeletion(origin: AlertOrigin? = nil) async {
        guard canUndo, let batch = undoStack.last else { return }
        let resolvedOrigin: AlertOrigin
        if let origin {
            resolvedOrigin = origin
        } else {
            resolvedOrigin = viewerItemID == nil ? .gallery : .viewer
        }

        isDeleting = true
        defer { isDeleting = false }
        undoStack.removeLast()

        let result = await trashService.restore(batch: batch)
        if let remainingBatch = result.remainingBatch {
            undoStack.append(remainingBatch)
        }

        if let folderURL {
            let restored = result.restoredItems.filter {
                $0.url.deletingLastPathComponent().standardizedFileURL == folderURL
            }
            let existingIDs = Set(items.map(\.id))
            items.append(contentsOf: restored.filter { !existingIDs.contains($0.id) })
            items = ImageScanner.sort(items)
            selection.subtract(Set(restored.map(\.id)))
        }

        if !result.failures.isEmpty {
            presentedError = PresentedError(
                title: "部分图片未能还原",
                message: result.failures.summary,
                origin: resolvedOrigin
            )
        }
    }

    func chooseArchiveDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择压缩包保存位置"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = archiveDirectory
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.archiveDirectory = url }
        }
    }

    func archiveSelection() async {
        guard !isArchiving && !isCopying, !isDeleting else { return }
        let targets = visibleSelection
        guard !targets.isEmpty else { return }

        isArchiving = true
        defer { isArchiving = false }
        let destination = nextArchiveDestination()

        do {
            try await archiveService.createArchive(files: targets.map(\.url), destination: destination)
            archiveResult = ArchiveResult(url: destination, fileCount: targets.count)
        } catch {
            presentedError = PresentedError(title: "无法创建压缩包", message: error.localizedDescription)
        }
    }

    func revealArchive(at url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func chooseCopyDirectory() {
        guard !isCopying else { return }
        let panel = NSOpenPanel()
        panel.title = "选择复制保存位置"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = copyDirectory
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.copyDirectory = url }
        }
    }

    func copySelection() async {
        guard !isCopying, !isArchiving, !isDeleting else { return }
        let targets = visibleSelection
        guard !targets.isEmpty else { return }

        isCopying = true
        defer { isCopying = false }
        do {
            let result = try await copyService.copy(files: targets.map(\.url), to: copyDirectory)
            if !result.copiedURLs.isEmpty {
                copyResult = CopyResult(urls: result.copiedURLs, directory: copyDirectory)
            }
            if !result.failures.isEmpty {
                presentedError = PresentedError(title: "部分图片未能复制", message: result.failures.summary)
            }
        } catch {
            presentedError = PresentedError(title: "无法复制图片", message: error.localizedDescription)
        }
    }

    func revealCopiedFiles(at urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func openViewer(for item: ImageItem) {
        displayInViewer(item)
        guard viewerItemID == item.id else { return }
        selection = [item.id]
        selectionAnchor = item.id
    }

    func displayInViewer(_ item: ImageItem) {
        guard filteredItems.contains(where: { $0.id == item.id }) else { return }
        viewerItemID = item.id
    }

    func closeViewer() {
        if pendingDeletion?.source == .viewer { pendingDeletion = nil }
        viewerItemID = nil
    }

    func showNextViewerItem() {
        navigateViewer(by: 1)
    }

    func showPreviousViewerItem() {
        navigateViewer(by: -1)
    }

    private func navigateViewer(by offset: Int) {
        let visible = filteredItems
        guard let viewerPosition else { return }
        let newIndex = viewerPosition + offset
        guard visible.indices.contains(newIndex) else { return }
        viewerItemID = visible[newIndex].id
    }

    private func filtersChanged() {
        selection = selection.intersection(Set(filteredItems.map(\.id)))
        if let selectionAnchor, !filteredItems.contains(where: { $0.id == selectionAnchor }) {
            self.selectionAnchor = nil
        }
        if let viewerItemID, !filteredItems.contains(where: { $0.id == viewerItemID }) {
            closeViewer()
        }
    }

    private func nextArchiveDestination() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "PicSift-\(formatter.string(from: Date()))"
        var destination = archiveDirectory.appendingPathComponent(base).appendingPathExtension("zip")
        var index = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = archiveDirectory
                .appendingPathComponent("\(base)-\(index)")
                .appendingPathExtension("zip")
            index += 1
        }
        return destination
    }
}
