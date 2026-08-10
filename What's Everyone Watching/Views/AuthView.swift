//  AuthView.swift
//  The 20b entry screen: ink poster, the pitch stated, two fields.
//
//  Why it looks like this:
//  · Dark, because this screen and Tonight are the same moment — the app
//    saying what it is for. The light interior then reads as arriving.
//  · Two fields, not three. "Full Name" exists so friends recognise you, so
//    ProfileSetupView asks for it after sign-up, where it means something.
//  · One red action. Everything else is a rule, a label, or ink.
//  · Sign up and sign in are the same two fields, so they are one screen with
//    the segmented switch the app already uses — a returning user is two taps
//    from home instead of hunting grey text at the bottom.
//
//  REQUIRES: SupabaseService.signInWithApple(idToken:nonce:fullName:) —
//  see the note at the bottom of this file.

import SwiftUI
import AuthenticationServices
import CryptoKit

struct AuthView: View {
    @EnvironmentObject private var supabase: SupabaseService

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = true
    @State private var showsPassword = false
    @State private var error: String?
    @State private var isLoading = false
    /// Held across the Apple round-trip so the identity token can be verified.
    @State private var appleNonce: String?

    @FocusState private var focus: Field?
    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.isEmpty && password.count >= (isSignUp ? 8 : 1) && !isLoading
    }

    var body: some View {
        ZStack {
            BingeTheme.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        poster
                        modeSwitch
                            .padding(.top, 30)
                        fields
                            .padding(.top, 26)
                        if let error {
                            Text(error)
                                .bingeBody(13)
                                .foregroundStyle(BingeTheme.accentTint)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 18)
                        }
                    }
                    .padding(.horizontal, BingeTheme.gutter)
                    .padding(.bottom, 24)
                }

                actions
            }
        }
        .foregroundStyle(BingeTheme.ground)
        .animation(.easeInOut(duration: 0.18), value: isSignUp)
    }

    // MARK: Poster

    private var poster: some View {
        VStack(alignment: .leading, spacing: 26) {
            BingeMark(height: 49, onDark: true)
                .padding(.top, 56)

            VStack(alignment: .leading, spacing: 0) {
                Text("Straight from your people")
                    .bingeLabel(11)
                    .foregroundStyle(BingeTheme.accentTint)
                    .padding(.bottom, 12)

                Text("WORD")
                    .bingeDisplay(46)
                    .foregroundStyle(BingeTheme.ground)

                Text("Six friends finished it. None stopped early. That's the whole pitch.")
                    .bingeBody(15)
                    .foregroundStyle(BingeTheme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .leading)
                    .padding(.top, 16)
            }
        }
    }

    // MARK: Mode

    private var modeSwitch: some View {
        HStack(spacing: 0) {
            modeCell("New here", selected: isSignUp) { isSignUp = true; error = nil }
            modeCell("Sign in", selected: !isSignUp) { isSignUp = false; error = nil }
        }
    }

    private func modeCell(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .bingeLabel(12)
                .foregroundStyle(selected ? BingeTheme.ink : BingeTheme.inkFaint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(selected ? BingeTheme.ground : Color.clear)
                .overlay(Rectangle().stroke(BingeTheme.ground, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Email").bingeLabel(11).foregroundStyle(BingeTheme.inkFaint)
                TextField("", text: $email, prompt: Text("you@example.com")
                    .foregroundColor(BingeTheme.inkMuted))
                    .bingeBody(16)
                    .foregroundStyle(BingeTheme.ground)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
                    .padding(.bottom, 9)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(focus == .email ? BingeTheme.accent : BingeTheme.inkMuted)
                            .frame(height: focus == .email ? 2 : 1)
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Password").bingeLabel(11).foregroundStyle(BingeTheme.inkFaint)
                    Spacer()
                    Button { showsPassword.toggle() } label: {
                        Text(showsPassword ? "Hide" : "Show")
                            .bingeLabel(11).foregroundStyle(BingeTheme.inkFaint)
                    }
                    .buttonStyle(.plain)
                }
                Group {
                    if showsPassword {
                        TextField("", text: $password, prompt: passwordPrompt)
                    } else {
                        SecureField("", text: $password, prompt: passwordPrompt)
                    }
                }
                .bingeBody(16)
                .foregroundStyle(BingeTheme.ground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(isSignUp ? .newPassword : .password)
                .submitLabel(.go)
                .focused($focus, equals: .password)
                .onSubmit { if canSubmit { handleAuth() } }
                .padding(.bottom, 9)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(focus == .password ? BingeTheme.accent : BingeTheme.inkMuted)
                        .frame(height: focus == .password ? 2 : 1)
                }
            }

            if !isSignUp {
                Button { /* password reset */ } label: {
                    Text("Forgot password").bingeLabel(11).foregroundStyle(BingeTheme.inkFaint)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var passwordPrompt: Text {
        Text(isSignUp ? "At least 8 characters" : "Your password")
            .foregroundColor(BingeTheme.inkMuted)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 14) {
            Rectangle().fill(BingeTheme.inkMuted.opacity(0.5)).frame(height: 1)

            Button(action: handleAuth) {
                HStack {
                    Text(isSignUp ? "Create account" : "Sign in").bingeLabel(13)
                    Spacer()
                    if isLoading {
                        ProgressView().tint(BingeTheme.ground)
                    } else {
                        Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundStyle(BingeTheme.ground)
                .padding(.horizontal, 20).padding(.vertical, 19)
                .background(canSubmit ? BingeTheme.accent : BingeTheme.accent.opacity(0.45))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .padding(.horizontal, BingeTheme.gutter)
            .padding(.top, 10)

            // Apple's button is a system control — it must keep its own shape and
            // label, so it gets the neutral treatment rather than the brand one.
            SignInWithAppleButton(.continue) { request in
                let nonce = Self.randomNonce()
                appleNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = Self.sha256(nonce)
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .padding(.horizontal, BingeTheme.gutter)

            if isSignUp {
                Text("By continuing you agree to the Terms and Privacy Policy.")
                    .bingeBody(11)
                    .foregroundStyle(BingeTheme.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BingeTheme.gutter)
            }
        }
        .padding(.bottom, 22)
        .background(BingeTheme.ink)
    }

    // MARK: Auth

    private func handleAuth() {
        guard canSubmit else { return }
        focus = nil
        error = nil
        isLoading = true
        Task {
            do {
                if isSignUp {
                    // Name is collected in ProfileSetupView, where it reads as
                    // "what your friends will see" rather than a form field.
                    _ = try await supabase.signUp(email: email, password: password, name: "")
                } else {
                    _ = try await supabase.signIn(email: email, password: password)
                }
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let err):
            // A cancel isn't an error worth shouting about.
            if (err as? ASAuthorizationError)?.code != .canceled {
                error = err.localizedDescription
            }
        case .success(let auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = appleNonce
            else {
                error = "Apple didn't return a usable credential."
                return
            }
            let displayName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            isLoading = true
            Task {
                do {
                    _ = try await supabase.signInWithApple(idToken: idToken,
                                                           nonce: nonce,
                                                           fullName: displayName.isEmpty ? nil : displayName)
                } catch {
                    self.error = error.localizedDescription
                }
                isLoading = false
            }
        }
    }

    // MARK: Nonce

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            guard status == errSecSuccess else { continue }
            if random < 252 {
                result.append(charset[Int(random) % charset.count])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

//  ─────────────────────────────────────────────────────────────────────────
//  SupabaseService needs one new method for the Apple button:
//
//      func signInWithApple(idToken: String, nonce: String, fullName: String?)
//          async throws -> User
//
//  POST \(supabaseURL)/auth/v1/token?grant_type=id_token
//      body: { "provider": "apple", "id_token": idToken, "nonce": nonce }
//  Decode the same shape signIn() already decodes (access_token, refresh_token,
//  user.id, user.email), store the tokens the same way, and set
//  profileSetupNeeded when the profile row has no name — passing fullName
//  through as the default so an Apple user usually skips typing it.
//
//  Also enable "Sign in with Apple" under Signing & Capabilities, and turn the
//  Apple provider on in the Supabase dashboard.
//  ─────────────────────────────────────────────────────────────────────────

#Preview {
    AuthView().environmentObject(SupabaseService.shared)
}
