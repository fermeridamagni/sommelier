import SwiftUI

// MARK: - SidebarSection

/// The top-level navigation sections in the app sidebar.
enum SidebarSection: String, CaseIterable, Identifiable {
    case home
    case library
    case search
    case downloads
    case settings

    var id: String { rawValue }

    /// Display name shown in the sidebar.
    var label: String {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .search: "Search"
        case .downloads: "Downloads"
        case .settings: "Settings"
        }
    }

    /// SF Symbol for the sidebar row.
    var systemImage: String {
        switch self {
        case .home: "house"
        case .library: "books.vertical"
        case .search: "magnifyingglass"
        case .downloads: "arrow.down.circle"
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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isSearchPresented = false

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(selectedSection: $selectedSection)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            } detail: {
                Group {
                    switch selectedSection {
                    case .home:
                        HomeView()
                    case .library:
                        LibraryView()
                    case .search:
                        // Fallback, should be handled by overlay, but just in case
                        LibraryView()
                    case .downloads:
                        DownloadsView()
                    case .settings:
                        SettingsView()
                    case .none:
                        HomeView()
                    }
                }
            }
            .navigationTitle("")
            
            if isSearchPresented {
                SearchDialogView(isPresented: $isSearchPresented)
                    .zIndex(100)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleSearchOverlay"))) { _ in
            isSearchPresented.toggle()
        }
        .background {
            // Invisible buttons for global shortcuts
            Button("") {
                if columnVisibility == .all {
                    columnVisibility = .detailOnly
                } else {
                    columnVisibility = .all
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .opacity(0)
            
            Button("") {
                isSearchPresented.toggle()
            }
            .keyboardShortcut("k", modifiers: .command)
            .opacity(0)
        }
    }
}

#Preview {
    MainView()
}
