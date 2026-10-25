import SwiftUI

struct FilterSidebar: View {
    @ObservedObject var store: AppStore

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                filterSection(
                    title: "图片格式",
                    selectAll: { store.selectedFormats = Set(ImageFormat.allCases) },
                    clear: { store.selectedFormats = [] }
                ) {
                    ForEach(ImageFormat.allCases) { format in
                        let count = store.items.lazy.filter { $0.format == format }.count
                        FilterRow(
                            title: format.displayName,
                            count: count,
                            isSelected: store.selectedFormats.contains(format),
                            isEnabled: count > 0
                        ) {
                            store.setFormat(format, included: !store.selectedFormats.contains(format))
                        }
                    }
                }

                filterSection(
                    title: "日期",
                    selectAll: { store.selectedDays = Set(store.availableDays.map(\.day)) },
                    clear: { store.selectedDays = [] }
                ) {
                    if store.availableDays.isEmpty {
                        Text("文件夹中没有可筛选的图片")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    } else {
                        ForEach(store.availableDays) { option in
                            FilterRow(
                                title: Self.dayFormatter.string(from: option.day),
                                subtitle: Self.weekdayFormatter.string(from: option.day),
                                count: option.count,
                                isSelected: store.selectedDays.contains(option.day)
                            ) {
                                store.setDay(option.day, included: !store.selectedDays.contains(option.day))
                            }
                        }
                        Text("优先采用拍摄日期，没有时使用文件修改日期。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                            .padding(.top, 6)
                            .padding(.bottom, 4)
                    }
                }
            }
            .padding(16)
        }
        .background(AppTheme.sidebar)
    }

    private func filterSection<Content: View>(
        title: String,
        selectAll: @escaping () -> Void,
        clear: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Menu {
                    Button("全选", action: selectAll)
                    Button("清空", action: clear)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 24)
                        .background(AppTheme.subtleFill, in: RoundedRectangle(cornerRadius: 7))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("筛选操作")
            }

            VStack(spacing: 3) {
                content()
            }
            .padding(5)
            .appCardBackground()
        }
    }
}

private struct FilterRow: View {
    let title: String
    var subtitle: String? = nil
    let count: Int
    let isSelected: Bool
    var isEnabled = true
    let action: () -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SelectionIndicator(isSelected: isSelected)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(isSelected ? 0.08 : 0.05), in: Capsule())
            }
            .padding(.horizontal, 9)
            .padding(.vertical, subtitle == nil ? 8 : 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(FilterRowButtonStyle(isSelected: isSelected, isHovering: hover.isHovering))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .onHover { hover.isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hover.isHovering)
        .animation(.easeOut(duration: 0.16), value: isSelected)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
    }
}

private struct FilterRowButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color
        if isSelected {
            fill = Color.accentColor.opacity(configuration.isPressed ? 0.24 : isHovering ? 0.20 : 0.15)
        } else if configuration.isPressed {
            fill = Color.primary.opacity(0.09)
        } else if isHovering {
            fill = AppTheme.hoverFill
        } else {
            fill = .clear
        }
        return configuration.label
            .background(RoundedRectangle(cornerRadius: 8).fill(fill))
    }
}
