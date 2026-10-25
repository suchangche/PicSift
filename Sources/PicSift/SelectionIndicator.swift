import SwiftUI

struct SelectionIndicator: View {
    let isSelected: Bool
    var highContrast = false
    var size: CGFloat = 19

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : highContrast ? Color.black.opacity(0.3) : Color.clear)
            Circle()
                .strokeBorder(
                    isSelected ? Color.accentColor : highContrast ? Color.white.opacity(0.88) : Color.secondary.opacity(0.42),
                    lineWidth: 1.35
                )
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.47, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: highContrast ? .black.opacity(0.38) : .clear, radius: 2, y: 1)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}
