//
//  SignInRequiredView.swift
//  MarkMind
//
//  View shown when user must sign in to access the app
//

import SwiftUI
import GoogleSignIn
import FirebaseCore
import FirebaseAuth

struct SignInRequiredView: View {
    @ObservedObject private var authManager = AuthManager.shared
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Sign In Required")
                .font(.title)
                .fontWeight(.bold)

            Text("All your files are stored securely in the cloud. Please sign in to access your documents.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 32)
            }

            Button {
                signIn()
            } label: {
                HStack {
                    if isSigningIn {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "person.crop.circle.badge.plus")
                    }
                    Text("Sign In with Google")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isSigningIn)
            .padding(.horizontal, 32)

            Spacer()

            Text("By signing in, you agree to our Terms of Service and Privacy Policy.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding()
    }

    private func signIn() {
        isSigningIn = true
        errorMessage = nil

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            errorMessage = "Unable to find root view controller"
            isSigningIn = false
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: FirebaseApp.app()?.options.clientID ?? ""
        )

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { [self] result, error in
            if let error = error {
                errorMessage = error.localizedDescription
                isSigningIn = false
                return
            }

            guard let idToken = result?.user.idToken?.tokenString else {
                errorMessage = "Failed to get ID token"
                isSigningIn = false
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result?.user.accessToken.tokenString ?? ""
            )

            Auth.auth().signIn(with: credential) { authResult, error in
                DispatchQueue.main.async {
                    isSigningIn = false
                    if let error = error {
                        errorMessage = error.localizedDescription
                        return
                    }
                    // Auth state change will handle navigation
                }
            }
        }
    }
}
