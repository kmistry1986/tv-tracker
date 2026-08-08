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
    @State private var showLaunch = true
    @Environment(\.accessibilityReduceMotion) var reduceMotion

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

            if showLaunch {
                BingeLaunchView()
                    .transition(.opacity)
            }
        }
        .task {
            await StreamingPlatformMapper.loadPlatforms()

            // Keep launch screen visible for ~1.5s or until auth resolves
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.3)) {
                showLaunch = false
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
    BingeMainTabView()
        .environmentObject(SupabaseService.shared)
}
