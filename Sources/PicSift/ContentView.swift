import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        ZStack {
            Group {
                if store.folderURL == nil {
                    WelcomeView(store: store)
                } else {
                    HStack(spacing: 0) {
                        if store.isSidebarVisible {
                            FilterSidebar(store: store)
                                .frame(width: 250)
                                .frame(maxHeight: .infinity)
                            Divider()
                        }
                        GalleryView(store: store)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .allowsHitTesting(store.viewerItemID == nil)

            if store.currentViewerItem != nil {
                ImageViewerView(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .zIndex(1)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.canvas)
        .animation(.easeInOut(duration: 0.16), value: store.viewerItemID == nil)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(nil) {
                        store.isSidebarVisible.toggle()
                    }
                } label: {
                    Label(
                        store.isSidebarVisible ? "隐藏侧边栏" : "显示侧边栏",
                        systemImage: "sidebar.left"
                    )
                }
                .help(store.isSidebarVisible ? "隐藏侧边栏" : "显示侧边栏")
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    store.chooseFolder()
                } label: {
                    Label("打开文件夹", systemImage: "folder")
                }
                .disabled(store.isDeleting || store.isCopying)
                .help("选择其他图片文件夹 (⌘O)")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await store.undoLastDeletion(origin: .gallery) }
                } label: {
                    Label("撤回删除", systemImage: "arrow.uturn.backward")
                }
                .disabled(!store.canUndo)
                .help("撤回上一批删除 (⌘Z)")
            }
        }
        .toolbarBackground(AppTheme.sidebar, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar(store.viewerItemID == nil ? .visible : .hidden, for: .windowToolbar)
        .navigationTitle(store.currentViewerItem?.url.lastPathComponent ?? store.folderURL?.lastPathComponent ?? "PicSift")
        .modifier(PicSiftAlerts(store: store, inViewer: false))
    }
}

private struct WelcomeView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 88, height: 88)
                .shadow(color: .black.opacity(0.16), radius: 16, y: 7)
                .accessibilityHidden(true)
            VStack(spacing: 9) {
                Text("PicSift")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                Text("筛选、查看并整理你的图片")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Button {
                store.chooseFolder()
            } label: {
                Label("选择图片文件夹", systemImage: "folder")
                    .frame(minWidth: 156)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
            Text("支持 JPEG、RAW、HEIC、PNG 等常见格式\n仅读取所选文件夹，不扫描子文件夹")
                .font(.callout)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
