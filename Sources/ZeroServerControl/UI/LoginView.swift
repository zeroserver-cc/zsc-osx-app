import SwiftUI
import AppKit

/// Identifies the login form's Window scene (see ZeroServerControlApp.swift).
/// This app is LSUIElement (no Dock icon, no regular window by default), so
/// the sign-in form needs an explicitly opened/closed Window rather than
/// relying on any default window SwiftUI would otherwise show.
enum AccountLoginWindow {
    static let id = "account-login"
}

struct LoginView: View {
    @ObservedObject var session: AccountSession
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 8) {
                AppLogoProvider.image
                    .resizable()
                    .frame(width: 48, height: 48)
                Text("Sign In to ZeroServer").font(.title2).bold()
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 10) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.vertical, 4)

            if let error = session.lastErrorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                if session.state == .signingIn {
                    ProgressView().controlSize(.small)
                }
                Button("Sign In") { Task { await session.signIn(email: email, password: password) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(email.isEmpty || password.isEmpty || session.state == .signingIn)
            }
        }
        .padding(24)
        .frame(width: 320)
        // The two-parameter `onChange(of:initial:_:)` closure form, and
        // SwiftUI's `dismissWindow` environment action, are both macOS 14+
        // only — this app's deployment target is macOS 13 (MenuBarExtra's
        // floor), so this uses the older single-value `onChange(of:perform:)`
        // overload plus a direct AppKit `close()` on the key window (this
        // form is the only window normally open in this menu-bar-only app,
        // so it's reliably the login window) instead.
        .onChange(of: session.state) { newState in
            if case .signedIn = newState { NSApp.keyWindow?.close() }
        }
    }
}
