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
            
            Spacer()
                .frame(minHeight: 200)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("ToggleSearchOverlay"), object: nil)
                } label: {
                    Label(SidebarSection.search.label, systemImage: SidebarSection.search.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button {
                    selectedSection = .downloads
                } label: {
                    Label(SidebarSection.downloads.label, systemImage: SidebarSection.downloads.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(selectedSection == .downloads ? Color.accentColor.opacity(0.8) : Color.clear)
                        .foregroundColor(selectedSection == .downloads ? .white : .primary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button {
                    selectedSection = .settings
                } label: {
                    Label(SidebarSection.settings.label, systemImage: SidebarSection.settings.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(selectedSection == .settings ? Color.accentColor.opacity(0.8) : Color.clear)
                        .foregroundColor(selectedSection == .settings ? .white : .primary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .listStyle(.sidebar)
        .navigationTitle("Sommelier")
        // Note: The global shortcut to toggle sidebar should actually be on the MainView or window level, but we can try attaching it here or in MainView.
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
