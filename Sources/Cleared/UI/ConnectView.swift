import SwiftUI

/// First run. The gh CLI path is one click because most people who need Cleared
/// already have `gh auth login` behind them.
///
/// The App Store build has no such path: the sandbox lets it neither run `gh`
/// nor read the login `gh` keeps. There a pasted token is the only way in, so
/// it is presented as the way in rather than as a fallback.
struct ConnectView: View {
    let model: AppModel
    @Environment(\.isSandboxedBuild) private var isSandboxed
    @Environment(\.openURL) private var open
    @State private var pastedToken = ""
    @State private var isWorking = false

    /// GitHub's new-token page with the scope and a name already filled in.
    private static let newTokenURL = URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=Cleared")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Cleared").font(.system(size: 15, weight: .semibold))
                Text("Clear held deploys and green PRs without opening a browser.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let notice = model.connectNotice {
                Label(notice, systemImage: "key.slash")
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.hold.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            // A saved-but-unreadable token is not the same as no token, and
            // silently showing the sign-in form for it is a lie.
            if case .denied(let status) = TokenStore.status() {
                VStack(alignment: .leading, spacing: 3) {
                    Label("A saved token exists but this build can't read it", systemImage: "lock.trianglebadge.exclamationmark")
                        .font(.system(size: 11, weight: .medium))
                    Text("\(Keychain.describe(status)). It was saved by a build with a different signature, which the Keychain entry's access list no longer matches. Connecting again replaces it.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Theme.hold.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            if !isSandboxed {
                Button {
                    isWorking = true
                    Task {
                        await model.signInFromGHCLI()
                        isWorking = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        if isWorking {
                            ProgressView().controlSize(.small).scaleEffect(0.6)
                        } else {
                            Image(systemName: "terminal")
                        }
                        Text("Use my gh CLI login")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isWorking || GHCLIImporter.locate() == nil)

                if GHCLIImporter.locate() == nil {
                    Label("gh CLI not found — paste a token instead.", systemImage: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Divider()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(isSandboxed ? "Connect with a personal access token" : "Or paste a personal access token")
                    .font(.system(size: 11, weight: .medium))
                SecureField("ghp_… or github_pat_…", text: $pastedToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit(submit)
                Text(isSandboxed
                    ? "Needs the repo scope. The App Store version can't read a gh CLI login, so it connects with a token. Stored in your login Keychain — never written to disk in the clear."
                    : "Needs the repo scope. Stored in your login Keychain — never written to disk in the clear.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    connectButton
                    Button("Create a token on GitHub…") { open(Self.newTokenURL) }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                    if isSandboxed, isWorking {
                        ProgressView().controlSize(.small).scaleEffect(0.6)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    /// The main action in the App Store build, a secondary one elsewhere.
    @ViewBuilder
    private var connectButton: some View {
        let isEmpty = pastedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isSandboxed {
            Button("Connect", action: submit)
                .buttonStyle(.borderedProminent)
                .disabled(isEmpty || isWorking)
        } else {
            Button("Connect", action: submit)
                .controlSize(.small)
                .disabled(isEmpty)
        }
    }

    private func submit() {
        let token = pastedToken
        pastedToken = ""
        isWorking = true
        Task {
            await model.signIn(token: token)
            isWorking = false
        }
    }
}

struct FailureView: View {
    let message: String
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Couldn't reach GitHub", systemImage: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Try again") { Task { await model.connect() } }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.small)
                Button("Disconnect") { model.signOut() }
                    .controlSize(.small)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(14)
    }
}
