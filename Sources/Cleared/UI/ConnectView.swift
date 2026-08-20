import SwiftUI

/// First run. The gh CLI path is one click because most people who need Cleared
/// already have `gh auth login` behind them.
struct ConnectView: View {
    let model: AppModel
    @State private var pastedToken = ""
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Cleared").font(.system(size: 15, weight: .semibold))
                Text("Clear held deploys and green PRs without opening a browser.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

            VStack(alignment: .leading, spacing: 5) {
                Text("Or paste a personal access token")
                    .font(.system(size: 11, weight: .medium))
                SecureField("ghp_… or github_pat_…", text: $pastedToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit(submit)
                Text("Needs the repo and workflow scopes. Stored in your login Keychain — never written to disk in the clear.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Connect", action: submit)
                    .controlSize(.small)
                    .disabled(pastedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
