import SwiftUI

/// Displays an SF Symbol icon representing a gaming platform.
///
/// Each platform maps to a specific SF Symbol and tint color,
/// providing consistent visual identification throughout the app.
///
/// Usage:
/// ```swift
/// PlatformIcon(platform: .steam)
/// PlatformIcon(platform: .epic, size: 24)
/// ```
struct PlatformIcon: View {

    /// The platform to display an icon for.
    let platform: Platform

    /// Icon size in points. Defaults to 16pt.
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: platform.systemImage)
            .font(.system(size: size))
            .foregroundStyle(platform.color)
            .accessibilityLabel(platform.displayName)
    }
}

#Preview {
    HStack(spacing: 16) {
        PlatformIcon(platform: .steam, size: 24)
        PlatformIcon(platform: .epic, size: 24)
        PlatformIcon(platform: .amazon, size: 24)
        PlatformIcon(platform: .macNative, size: 24)
        PlatformIcon(platform: .windowsApp, size: 24)
    }
    .padding()
}
