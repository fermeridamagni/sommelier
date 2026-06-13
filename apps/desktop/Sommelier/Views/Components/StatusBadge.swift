import SwiftUI

/// Small capsule badge displaying a game's current status.
///
/// Shows a colored dot and text label. Active states (running, downloading)
/// feature a pulsing animation on the dot to indicate ongoing activity.
///
/// Usage:
/// ```swift
/// StatusBadge(status: .running)
/// StatusBadge(status: .downloading)
/// ```
struct StatusBadge: View {

    /// The game status to display.
    let status: GameStatus

    /// Drives the pulsing animation for active states.
    @State private var isPulsing = false

    var body: some View {
        if status != .idle {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isPulsing && isActiveState ? 1.4 : 1.0)
                    .opacity(isPulsing && isActiveState ? 0.6 : 1.0)
                    .animation(
                        isActiveState
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: isPulsing
                    )

                Text(label)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.25), in: Capsule())
            .onAppear {
                if isActiveState {
                    isPulsing = true
                }
            }
        }
    }

    // MARK: - Computed Properties

    /// Color associated with each status.
    private var color: Color {
        switch status {
        case .idle: .gray
        case .downloading: .blue
        case .installing: .orange
        case .running: .green
        case .updating: .purple
        case .error: .red
        }
    }

    /// Display label for each status.
    private var label: String {
        switch status {
        case .idle: "Idle"
        case .downloading: "Downloading"
        case .installing: "Installing"
        case .running: "Running"
        case .updating: "Updating"
        case .error: "Error"
        }
    }

    /// Whether this status represents an active/in-progress state.
    private var isActiveState: Bool {
        switch status {
        case .running, .downloading, .installing, .updating: true
        default: false
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        StatusBadge(status: .running)
        StatusBadge(status: .downloading)
        StatusBadge(status: .installing)
        StatusBadge(status: .updating)
        StatusBadge(status: .error)
    }
    .padding()
    .background(.black)
}
