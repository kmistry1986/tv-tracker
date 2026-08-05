import SwiftUI

@main struct MyApp: App {
    @StateObject private var supabase = SupabaseService.shared

    var body: some Scene {
        WindowGroup {
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
    }
}

struct MainTabView: View {
    @StateObject private var supabase = SupabaseService.shared
    
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }

            WatchlistView()
                .tabItem {
                    Label("Watchlist", systemImage: "bookmark.fill")
                }

            FriendsView()
                .tabItem {
                    Label("Friends", systemImage: "person.2.fill")
                }

            ActivityFeedView()
                .tabItem {
                    Label("Activity", systemImage: "sparkles")
                }

            ImportManagementView()
                .tabItem {
                    Label("Import", systemImage: "arrow.down.doc")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
        }
    }
}

struct ProfileView: View {
    @StateObject private var supabase = SupabaseService.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text(supabase.currentUser?.name ?? "User")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(supabase.currentUser?.email ?? "")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding()
                
                Divider()
                
                ScrollView {
                    VStack(spacing: 0) {
                        NavigationLink(destination: FriendsView()) {
                            HStack {
                                Image(systemName: "person.2")
                                Text("Friends")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding()
                            .foregroundColor(.primary)
                        }

                        Divider()

                        NavigationLink(destination: EmptyView()) {
                            HStack {
                                Image(systemName: "gear")
                                Text("Settings")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding()
                            .foregroundColor(.primary)
                        }
                    }
                }
                
                Spacer()
                
                Button(action: signOut) {
                    Text("Sign Out")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle("Profile")
        }
    }
    
    private func signOut() {
        supabase.signOut()
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
