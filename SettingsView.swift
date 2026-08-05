import SwiftUI

struct SettingsView: View {
    @StateObject private var supabase = SupabaseService.shared
    @State private var selectedPlatformIds: [Int] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var showSuccess = false
    @State private var error: String?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading {
                    VStack {
                        ProgressView()
                        Text("Loading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                } else {
                    Form {
                        Section {
                            StreamingPlatformSelector(selectedPlatformIds: $selectedPlatformIds)
                                .padding(.vertical, 8)
                        } header: {
                            Text("Streaming Services")
                        } footer: {
                            Text("Select the streaming platforms you have access to. This helps filter and highlight content available on your services.")
                                .font(.caption)
                        }
                        
                        Section {
                            Button(action: saveSettings) {
                                HStack {
                                    Spacer()
                                    if isSaving {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text("Save Changes")
                                            .fontWeight(.semibold)
                                    }
                                    Spacer()
                                }
                            }
                            .listRowBackground(Color.blue)
                            .foregroundColor(.white)
                            .disabled(isSaving)
                        }
                        
                        if showSuccess {
                            Section {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Settings saved successfully!")
                                        .font(.subheadline)
                                }
                            }
                        }
                        
                        if let error = error {
                            Section {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text(error)
                                        .font(.subheadline)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadUserPlatforms()
            }
        }
    }
    
    private func loadUserPlatforms() {
        guard let userId = supabase.currentUser?.id else { return }
        
        isLoading = true
        error = nil
        
        Task {
            do {
                let platformIds = try await supabase.getUserPlatforms(userId: userId)
                DispatchQueue.main.async {
                    self.selectedPlatformIds = platformIds
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = "Failed to load platforms: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func saveSettings() {
        guard let userId = supabase.currentUser?.id else { return }
        
        isSaving = true
        error = nil
        showSuccess = false
        
        Task {
            do {
                try await supabase.saveUserPlatforms(userId: userId, platformIds: selectedPlatformIds)
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.showSuccess = true
                    
                    // Hide success message after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.showSuccess = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = "Failed to save: \(error.localizedDescription)"
                    self.isSaving = false
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
