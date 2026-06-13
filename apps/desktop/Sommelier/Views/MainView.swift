import SwiftUI

// MARK: - SidebarSection

/// The top-level navigation sections in the app sidebar.
enum SidebarSection: String, CaseIterable, Identifiable {
    case home
    case library
    case settings

    var id: String { rawValue }

    /// Display name shown in the sidebar.
    var label: String {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .settings: "Settings"
        }
    }

    /// SF Symbol for the sidebar row.
    var systemImage: String {
        switch self {
        case .home: "house"
        case .library: "books.vertical"
        case .settings: "gear"
        }
    }
}

// MARK: - MainView

/// Root application view using `NavigationSplitView` with a sidebar.
///
/// Routes between Home (dashboard), Library (game grid), and Settings
/// based on the user's sidebar selection. This view is shown after
/// onboarding and authentication are complete.
struct MainView: View {

    /// The currently selected sidebar section.
    @State private var selectedSection: SidebarSection? = .home

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedSection: $selectedSection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selectedSection {
                case .home:
                    HomeView()
                case .library:
                    LibraryView()
                case .settings:
                    SettingsView()
                case .none:
                    HomeView()
                }
            }
        }
        .navigationTitle("")
    }
}

#Preview {
    MainView()
}
