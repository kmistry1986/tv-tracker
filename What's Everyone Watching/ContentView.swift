import SwiftUI

@main struct MyApp: App {
    @StateObject private var supabase = SupabaseService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(supabase)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var supabase: SupabaseService

    var body: some View {
        ZStack {
            if supabase.isLoggedIn {
                if supabase.profileSetupNeeded {
                    ProfileSetupView()
                        .environmentObject(supabase)
                } else {
                    MainTabView()
                        .environmentObject(supabase)
                }
            } else {
                AuthView()
                    .environmentObject(supabase)
            }
        }
        .task {
            await StreamingPlatformMapper.loadPlatforms()
        }
    }
}

// Custom App Tab enum
enum AppTab: String, CaseIterable {
    case home = "Home"
    case library = "Library"
    case watchlist = "Watchlist"
    case friends = "Friends"
    case activity = "Activity"
    case you = "You"
}

struct MainTabView: View {
    @StateObject private var supabase = SupabaseService.shared
    @State private var selectedTab: AppTab = .home
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content
            Group {
                switch selectedTab {
                case .home:
                    HomeView()
                case .library:
                    LibraryView()
                case .watchlist:
                    WatchlistView()
                case .friends:
                    FriendsView()
                case .activity:
                    ActivityFeedView()
                case .you:
                    ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Custom tab bar
            CustomTabBar(selection: $selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

struct CustomTabBar: View {
    @Binding var selection: AppTab
    
    var body: some View {
        VStack(spacing: 0) {
            Rule(strong: true)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        Button {
                            selection = tab
                        } label: {
                            Text(tab.rawValue)
                                .font(Theme.semi(10))
                                .tracking(1.2)
                                .textCase(.uppercase)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .foregroundStyle(selection == tab ? Theme.accent : Theme.inkMuted)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        
                        if tab != AppTab.allCases.last {
                            Rectangle()
                                .fill(Theme.hairline)
                                .frame(width: 1)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
            .background(Theme.ground)
        }
        .background(Theme.ground)
    }
}

struct ProfileView: View {
    @StateObject private var supabase = SupabaseService.shared
    @State private var showSettings = false
    @State private var showClearDataConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .lastTextBaseline) {
                Text("YOU").displayTitle(34)
                Spacer()
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 14)
            
            Rule(strong: true)
            
            // Profile section
            HStack(spacing: 14) {
                Text((supabase.currentUser?.name ?? "U").prefix(2).uppercased())
                    .headline(14)
                    .frame(width: 44, height: 44)
                    .background(Theme.ink)
                    .foregroundStyle(Theme.ground)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(supabase.currentUser?.name ?? "User")
                        .headline(18)
                    Text(supabase.currentUser?.email ?? "")
                        .bodyCopy(12)
                        .foregroundStyle(Theme.inkMuted)
                }
                
                Spacer()
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, Theme.Space.lg)
            
            Rule(strong: true)
            
            ScrollView {
                VStack(spacing: 0) {
                    // Streaming Platforms
                    Button(action: { showSettings = true }) {
                        HStack {
                            Text("Streaming Platforms")
                                .headline(15)
                            Spacer()
                            Text("→")
                                .font(Theme.heavy(15))
                                .foregroundStyle(Theme.inkMuted)
                        }
                        .padding(.horizontal, Theme.gutter)
                        .padding(.vertical, Theme.Space.lg)
                        .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                    
                    Rule()
                    
                    // Clear Data
                    Button(action: { showClearDataConfirmation = true }) {
                        HStack {
                            Text("Clear My Data")
                                .headline(15)
                            Spacer()
                        }
                        .padding(.horizontal, Theme.gutter)
                        .padding(.vertical, Theme.Space.lg)
                        .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    
                    Rule()
                }
            }
            
            Spacer()
            
            // Sign out button
            PrimaryButton(title: "Sign Out") {
                signOut()
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, Theme.Space.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.ground)
        .foregroundStyle(Theme.ink)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("Clear All Data?", isPresented: $showClearDataConfirmation) {
            Button("Delete", role: .destructive) {
                clearUserData()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete all your library, watchlist, and episode data. This action cannot be undone.")
        }
    }

    private func signOut() {
        supabase.signOut()
    }

    private func clearUserData() {
        Task {
            do {
                try await supabase.clearUserData()
                print("User data cleared successfully")
            } catch {
                print("Error clearing user data: \(error)")
            }
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("Hello, world!")
            .padding()
    }
}

#Preview {
    MainTabView()
        .environmentObject(SupabaseService.shared)
}
