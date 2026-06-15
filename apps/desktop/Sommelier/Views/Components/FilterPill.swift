import SwiftUI

/// Individual filter pill button.
struct FilterPill: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var count: Int? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)

                if let count {
                    Text("\(count)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            isSelected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Capsule())
            .background(
                isSelected ? Color.accentColor.opacity(0.2) : Color.clear,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
