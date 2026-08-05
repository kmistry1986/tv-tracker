import SwiftUI

struct AuthView: View {
    @StateObject private var supabase = SupabaseService.shared
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var isSignUp = false
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.05), Color.purple.opacity(0.05)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        Image(systemName: "tv.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.blue)

                        Text("TV Tracker")
                            .font(.system(size: 28, weight: .bold))

                        Text(isSignUp ? "Create your account" : "Welcome back")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 32)

                    VStack(spacing: 16) {
                        if isSignUp {
                            CustomTextField(
                                placeholder: "Full Name",
                                text: $name,
                                icon: "person.fill"
                            )
                        }

                        CustomTextField(
                            placeholder: "Email",
                            text: $email,
                            icon: "envelope.fill",
                            keyboardType: .emailAddress
                        )

                        CustomSecureField(
                            placeholder: "Password",
                            text: $password,
                            icon: "lock.fill"
                        )
                    }
                    .padding(.bottom, 24)

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

                    Button(action: handleAuth) {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isSignUp ? "Sign Up" : "Sign In")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(isLoading)

                    Spacer()

                    VStack(spacing: 8) {
                        Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                            .font(.caption)
                            .foregroundColor(.gray)

                        Button(action: {
                            isSignUp.toggle()
                            error = nil
                        }) {
                            Text(isSignUp ? "Sign In" : "Sign Up")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(24)
            }
        }
    }

    private func handleAuth() {
        guard !email.isEmpty && !password.isEmpty else {
            error = "Please fill in all fields"
            return
        }

        if isSignUp && name.isEmpty {
            error = "Please enter your name"
            return
        }

        error = nil
        isLoading = true

        Task {
            do {
                if isSignUp {
                    try await supabase.signUp(email: email, password: password, name: name)
                } else {
                    try await supabase.signIn(email: email, password: password)
                }
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct CustomTextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .autocapitalization(.none)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct CustomSecureField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    @State private var isSecure = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)

            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }

            Button(action: { isSecure.toggle() }) {
                Image(systemName: isSecure ? "eye.slash" : "eye")
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

#Preview {
    AuthView()
}
