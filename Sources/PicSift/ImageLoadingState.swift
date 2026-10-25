import AppKit
import Foundation

@MainActor
final class ImageLoadingState: ObservableObject {
    @Published var image: NSImage?
    @Published var isLoading = false
    @Published var failed = false
}
