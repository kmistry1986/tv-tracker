//  BingeSettingsView.swift
//  Settings sheet: profile, streaming platforms, data, account.
//  Wired to getUserProfile / updateUserProfile / getStreamingPlatforms /
//  getUserPlatforms / saveUserPlatforms / clearUserData / signOut.

import SwiftUI
import Combine

@MainActor
final class BingeSettingsEngine: ObservableObject {
    @Published var displayName = ""
    @Published var bio = ""
    @Published var isPublic = true

    @Published var platforms: [StreamingPlatformRow] = []
    @Published var selected: Set<Int> = []

    @Published var isLoading = false
    @Published var isSaving = false
    @Published var message: String?
    @Published var showClearConfirm = false
    @Published var isReconciling = false

    private let supabase = SupabaseService.shared

    func load() async {
        guard let userId = supabase.currentUser?.id else { return }
        isLoading = true
        defer { isLoading = false }

        if let profile = try? await supabase.getUserProfile(userId: userId) {
            displayName = profile.displayName
            bio = profile.bio ?? ""
            isPublic = profile.isPublic
        } else if let email = supabase.currentUser?.email {
            displayName = email.split(separator: "@").first.map(String.init) ?? ""
        }

        platforms = (try? await supabase.getStreamingPlatforms()) ?? []
        selected = Set((try? await supabase.getUserPlatforms(userId: userId)) ?? [])

        // Merge Max into HBO Max if both exist
        try? await supabase.mergeMaxIntoHBOMax()

        // Clean up orphaned watchlist entries
        try? await supabase.cleanupOrphanedWatchlist()
    }

    func toggle(_ id: Int) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func save() async {
        guard let userId = supabase.currentUser?.id else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await supabase.updateUserProfile(userId: userId,
                                                 displayName: displayName.isEmpty ? nil : displayName,
                                                 bio: bio.isEmpty ? nil : bio,
                                                 isPublic: isPublic)
            try await supabase.saveUserPlatforms(userId: userId, platformIds: Array(selected))

            // Update currentUser with new display name
            if let user = supabase.currentUser {
                supabase.currentUser = User(
                    id: user.id,
                    email: user.email,
                    name: displayName.isEmpty ? user.email : displayName,
                    avatarUrl: user.avatarUrl
                )
            }

            message = "Saved."
        } catch {
            message = error.localizedDescription
        }
    }

    func clearData() async {
        do {
            try await supabase.clearUserData()
            message = "Watch history cleared."
        } catch {
            message = error.localizedDescription
        }
    }

    func signOut() { supabase.signOut() }

    func reconcile() async {
        isReconciling = true
        defer { isReconciling = false }
        await supabase.reconcileWatchlistWithTables()
        message = "Reconciliation complete."
    }
}

struct BingeSettingsView: View {
    @StateObject private var engine = BingeSettingsEngine()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("Settings").bingeDisplay(34)
                Spacer()
                Button { dismiss() } label: {
                    Text("Done").bingeLabel(11).foregroundStyle(BingeTheme.accent)
                        .padding(.vertical, 10).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, BingeTheme.gutter).padding(.top, 4).padding(.bottom, 14)
            BingeRule(strong: true)

            ScrollView {
                LazyVStack(spacing: 0) {
                    profileSection
                    BingeRule(strong: true)
                    platformsSection
                    BingeRule(strong: true)
                    dataSection
                }
            }

            if let message = engine.message {
                BingeRule(strong: true)
                Text(message).bingeBody(12).foregroundStyle(BingeTheme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 10)
            }

            BingeRule(strong: true)
            BingePrimaryButton(title: engine.isSaving ? "Saving…" : "Save changes") {
                Task { await engine.save() }
            }
            .padding(.horizontal, BingeTheme.gutter)
            .padding(.top, 12).padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BingeTheme.ground)
        .foregroundStyle(BingeTheme.ink)
        .task { await engine.load() }
        .confirmationDialog("Clear your watch history?",
                            isPresented: $engine.showClearConfirm,
                            titleVisibility: .visible) {
            Button("Clear everything", role: .destructive) { Task { await engine.clearData() } }
            Button("Keep it", role: .cancel) { }
        } message: {
            Text("Every show, movie and episode you've logged is deleted. Friends and watchlist stay. This can't be undone.")
        }
    }

    // MARK: Profile

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            BingeSectionHeader(title: "Profile")

            field(label: "Display name", text: $engine.displayName,
                  placeholder: "What friends see")

            field(label: "Bio", text: $engine.bio,
                  placeholder: "One line, optional")

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Discoverable").bingeHeadline(15)
                    Text("Friends can find you by name. Turn this off and only people you invite can add you.")
                        .bingeBody(12).foregroundStyle(BingeTheme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $engine.isPublic)
                    .labelsHidden()
                    .tint(BingeTheme.accent)
            }
            .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 14)
        }
    }

    private func field(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).bingeLabel(10).foregroundStyle(BingeTheme.inkMuted)
            TextField(placeholder, text: text)
                .bingeBody(14)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .padding(.horizontal, 12).padding(.vertical, 12)
                .frame(minHeight: BingeTheme.minTap)
                .overlay(Rectangle().stroke(BingeTheme.ink, lineWidth: 1))
        }
        .padding(.horizontal, BingeTheme.gutter).padding(.bottom, 16)
    }

    // MARK: Platforms

    private var platformsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            BingeSectionHeader(title: "Your services",
                               trailing: engine.selected.isEmpty ? nil : "\(engine.selected.count) on")

            Text("Tonight only recommends things you can actually stream. Pick what you pay for.")
                .bingeBody(12).foregroundStyle(BingeTheme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BingeTheme.gutter).padding(.bottom, 12)

            if engine.isLoading {
                ProgressView().tint(BingeTheme.accent)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if engine.platforms.isEmpty {
                Text("No services available.").bingeBody(13)
                    .foregroundStyle(BingeTheme.inkMuted)
                    .padding(.horizontal, BingeTheme.gutter).padding(.bottom, 16)
            } else {
                ForEach(engine.platforms, id: \.id) { p in
                    BingeRule()
                    Button { engine.toggle(p.id) } label: {
                        HStack {
                            Text(p.display_name).bingeHeadline(15)
                            Spacer()
                            Text(engine.selected.contains(p.id) ? "On" : "Off")
                                .bingeLabel(11)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .foregroundStyle(engine.selected.contains(p.id)
                                                 ? BingeTheme.ground : BingeTheme.inkMuted)
                                .background(engine.selected.contains(p.id)
                                            ? BingeTheme.ink : Color.clear)
                                .overlay(Rectangle().stroke(engine.selected.contains(p.id)
                                                            ? Color.clear : BingeTheme.hairline,
                                                            lineWidth: 1))
                        }
                        .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 12)
                        .frame(minHeight: BingeTheme.minTap)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                BingeRule()
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: Data & account

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            BingeSectionHeader(title: "Data")

            VStack(alignment: .leading, spacing: 10) {
                Text("Watch history comes from a Netflix CSV export, not a live connection. Re-import any time from the You tab.")
                    .bingeBody(12).foregroundStyle(BingeTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    BingeChip(title: "Clear history", muted: true) {
                        engine.showClearConfirm = true
                    }
                    BingeChip(title: "Reconcile watchlist", muted: true) {
                        Task { await engine.reconcile() }
                    }
                    BingeChip(title: "Sign out") { engine.signOut() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BingeTheme.gutter).padding(.vertical, 12)
        }
    }
}
