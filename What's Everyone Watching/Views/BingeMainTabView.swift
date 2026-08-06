//  BingeMainTabView.swift
//  Three tabs instead of seven. Nothing is deleted — Library, Watchlist,
//  Activity, Import and Profile all still exist, they're nested one level down.
//
//  TO SWITCH THE APP OVER, change ONE line in ContentView.swift:
//      MainTabView()        →  BingeMainTabView()
//  Change it back any time. Your original MainTabView is untouched.

import SwiftUI

struct BingeMainTabView: View {
    @StateObject private var supabase = SupabaseService.shared
    @State private var tab: BingeTab = .tonight

    var body: some View {
        Group {
            switch tab {
            case .tonight:
                NavigationStack { BingeTonightView(tab: $tab) }
            case .friends:
                NavigationStack { BingeFriendsTab(tab: $tab) }
            case .you:
                NavigationStack { BingeYouView(tab: $tab) }
            }
        }
        .environmentObject(supabase)
        .ignoresSafeArea(edges: .bottom)
        .tint(BingeTheme.accent)
    }
}

// MARK: - Friends tab
// Your ActivityFeedView and FriendsView, behind one segmented control.

struct BingeFriendsTab: View {
    @Binding var tab: BingeTab
    @State private var section = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("Friends").bingeDisplay(34)
                Spacer()
            }
            .padding(.horizontal, BingeTheme.gutter).padding(.top, 8).padding(.bottom, 14)
            BingeRule(strong: true)

            BingeSegmented(options: ["Activity", "People"], selection: $section)
                .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 12)
            BingeRule(strong: true)

            // Your existing views, restyled by the surrounding chrome.
            // Their own NavigationStacks are suppressed by the toolbar hiding below.
            Group {
                if section == 0 { BingeFriendsFeed(tab: $tab) } else { BingePeopleTab() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BingeTheme.ground)
        .foregroundStyle(BingeTheme.ink)
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 5) }
        .safeAreaInset(edge: .bottom, spacing: 0) { BingeTabBar(selection: $tab) }
    }
}

// MARK: - You tab
// Library + Watchlist + Import + Profile, folded into one screen.

struct BingeYouTab: View {
    @EnvironmentObject private var supabase: SupabaseService
    @Binding var tab: BingeTab
    @State private var section = 0
    @State private var showSettings = false
    @State private var showImport = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 12) {
                    Text(initials).bingeHeadline(14)
                        .frame(width: 44, height: 44)
                        .background(BingeTheme.ink).foregroundStyle(BingeTheme.ground)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(supabase.currentUser?.name ?? "You").bingeHeadline(18)
                        Text(supabase.currentUser?.email ?? "")
                            .bingeBody(12).foregroundStyle(BingeTheme.inkMuted)
                    }
                }
                Spacer()
                Button { showSettings = true } label: {
                    Text("Settings").bingeLabel(11).foregroundStyle(BingeTheme.inkMuted)
                        .padding(.vertical, 10).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, BingeTheme.gutter).padding(.top, 8).padding(.bottom, 16)
            BingeRule(strong: true)

            BingeSegmented(options: ["Library", "Watchlist"], selection: $section)
                .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 12)
            BingeRule(strong: true)

            Group {
                if section == 0 { LibraryView() } else { WatchlistView() }
            }
            .toolbar(.hidden, for: .navigationBar)

            BingeRule(strong: true)
            HStack(spacing: 8) {
                BingeChip(title: "Import") { showImport = true }
                BingeChip(title: "Platforms", muted: true) { showSettings = true }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BingeTheme.ground)
        .foregroundStyle(BingeTheme.ink)
        .navigationBarHidden(true)
        .safeAreaInset(edge: .bottom, spacing: 0) { BingeTabBar(selection: $tab) }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showImport) { ImportManagementView() }
    }

    private var initials: String {
        let name = supabase.currentUser?.name ?? "You"
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }
}
