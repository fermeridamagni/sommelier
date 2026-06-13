import SwiftUI

/// Sidebar navigation for the main `NavigationSplitView`.
///
/// Displays the primary sections (Home, Library) separated from
/// Settings by a divider. Uses `.listStyle(.sidebar)` for the
/// native macOS sidebar appearance with translucent material.
struct SidebarView: View {

    /// Binding to the parent's selected sidebar section.
    @Binding var selectedSection: SidebarSection?

    var body: some View {
        List(selection: $selectedSection) {
            // Primary navigation
            Section {
                ForEach([SidebarSection.home, .library], id: \.self) { section in
                    Label(section.label, systemImage: section.systemImage)
                        .tag(section)
                }
            }

            // Utility section
            Section {
                Label(SidebarSection.settings.label, systemImage: SidebarSection.settings.systemImage)
                    .tag(SidebarSection.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Sommelier")
    }
}

#Preview {
    @Previewable @State var selection: SidebarSection? = .home
    NavigationSplitView {
        SidebarView(selectedSection: $selection)
    } detail: {
        Text("Detail")
    }
}
