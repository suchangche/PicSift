import SwiftUI

private func appColor(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .accessibilityHighContrastDarkAqua]) != nil
        return isDark ? dark : light
    })
}

enum AppTheme {
    static let canvas = appColor(
        light: NSColor(calibratedRed: 0.949, green: 0.957, blue: 0.969, alpha: 0.98),
        dark: NSColor(calibratedRed: 0.098, green: 0.106, blue: 0.122, alpha: 0.98)
    )
    static let sidebar = appColor(
        light: NSColor(calibratedRed: 0.969, green: 0.973, blue: 0.980, alpha: 0.98),
        dark: NSColor(calibratedRed: 0.110, green: 0.122, blue: 0.141, alpha: 0.98)
    )
    static let elevated = appColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.97),
        dark: NSColor(calibratedRed: 0.137, green: 0.149, blue: 0.169, alpha: 0.97)
    )
    static let card = appColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.96),
        dark: NSColor(calibratedRed: 0.153, green: 0.165, blue: 0.188, alpha: 0.96)
    )
    static let subtleFill = Color.primary.opacity(0.05)
    static let hoverFill = Color.primary.opacity(0.065)
    static let cardBorder = Color.primary.opacity(0.06)
    static let hairline = Color.primary.opacity(0.08)
    static let cardShadow = Color.black.opacity(0.08)
}

@MainActor
final class HoverState: ObservableObject {
    @Published var isHovering = false
}

private struct AppCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
            }
            .shadow(color: AppTheme.cardShadow, radius: 10, y: 4)
    }
}

private struct ViewerControlBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.09), lineWidth: 1)
            }
    }
}

extension View {
    func appCardBackground() -> some View {
        modifier(AppCardBackground())
    }

    func viewerControlBackground(cornerRadius: CGFloat = 10) -> some View {
        modifier(ViewerControlBackground(cornerRadius: cornerRadius))
    }
}
