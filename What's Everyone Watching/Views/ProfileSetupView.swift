import SwiftUI

struct ProfileSetupView: View {
    @StateObject private var supabase = SupabaseService.shared
    @State private var displayName = ""
    @State private var bio = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.05), Color.green.opacity(0.05)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)

                        Text("Complete Your Profile")
                            .font(.system(size: 22, weight: .bold))

                        Text("Set up your public profile so friends can find you")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 28)

                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Display Name")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.gray)

                            HStack(spacing: 12) {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.blue)
                                    .frame(width: 20)

                                TextField("How should friends know you?", text: $displayName)
                                    .autocapitalization(.words)
                            }
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Bio (optional)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.gray)

                            HStack(spacing: 12) {
                                VStack(alignment: .leading) {
                                    TextEditor(text: $bio)
                                        .frame(height: 100)
                                }
                                .padding(12)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                            }
                        }
                    }
                    .padding(.horizontal, 0)

                    Spacer()

                    if let error = error {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.bottom, 16)
                    }

                    Button(action: completeSetup) {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Continue")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(displayName.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(isLoading || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(24)
            }
        }
    }

    private func completeSetup() {
        guard let userId = supabase.currentUser?.id else { return }
        guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        error = nil
        isLoading = true

        Task {
            do {
                try await supabase.completeProfileSetup(
                    userId: userId,
                    displayName: displayName,
                    bio: bio.trimmingCharacters(in: .whitespaces).isEmpty ? nil : bio
                )
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    ProfileSetupView()
}
