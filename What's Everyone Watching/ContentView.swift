import SwiftUI

@main struct MyApp: App {
    @StateObject private var supabase = SupabaseService.shared

    init() {
        BingeTheme.debugPrintFontNames()
    }

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
                    BingeMainTabView()
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


struct ContentView: View {
    var body: some View {
        Text("Hello, world!")
            .padding()
    }
}

#Preview {
    BingeMainTabView()
        .environmentObject(SupabaseService.shared)
}
