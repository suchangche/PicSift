import SwiftUI

@main
@MainActor
struct PicSiftApp: App {
    @StateObject private var store = AppStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("PicSift", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 980, idealWidth: 1280, minHeight: 680, idealHeight: 820)
                .onAppear {
                    appDelegate.openMainWindow = {
                        openWindow(id: "main")
                    }
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开文件夹…") { store.chooseFolder() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤回删除") {
                    Task { await store.undoLastDeletion() }
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!store.canUndo)
            }
            CommandGroup(after: .pasteboard) {
                Button("全选当前筛选结果") { store.selectAllFiltered() }
                    .keyboardShortcut("a", modifiers: .command)
                    .disabled(store.filteredItems.isEmpty)
            }
        }
    }
}
