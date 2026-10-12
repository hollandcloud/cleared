import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = Settings.shared
    @State private var pollSeconds: Double = Settings.shared.approvalInterval
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?
    @State private var repoToPin = ""
    @State private var pinRejected = false
    @State private var rediscovery: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Cleared").font(.system(size: 13, weight: .semibold))
                Spacer()
                if let login = model.login {
                    Text("@\(login)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            Form {
                general
                checking
                acting
                repositories
                account
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            HStack {
                Text("Cleared \(AppEnvironment.version)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 400, height: 600)
        .onChange(of: settings.discoveryDays) { scheduleRediscovery() }
        .onChange(of: settings.repoLimit) { scheduleRediscovery() }
    }

    private var general: some View {
        Section {
            Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                .disabled(!LoginItem.isInstalled && !launchAtLogin)
            if let loginItemError {
                caption(loginItemError)
            } else if !LoginItem.isInstalled {
                caption("Move Cleared to Applications to turn this on (make install does it). A copy in a build folder would register a path the next build removes.")
            }
        }
    }

    private var checking: some View {
        Section("Checking") {
            VStack(alignment: .leading, spacing: 2) {
                Slider(value: $pollSeconds, in: 10...300, step: 10) {
                    Text("Every \(Int(pollSeconds))s")
                }
                .onChange(of: pollSeconds) { _, new in settings.approvalInterval = new }
                caption("Slows to every \(Int(pollSeconds) * settings.backgroundMultiplier)s while the menu is closed. Unchanged repositories answer from cache and cost nothing.")
            }

            Toggle("Notify when something starts holding", isOn: $settings.notifyOnHold)
            Toggle("Notify when a run fails", isOn: $settings.notifyOnFailure)
            Toggle("Show failed runs in the queue", isOn: $settings.showFailures)
        }
    }

    private var acting: some View {
        Section("Clearing and merging") {
            Picker("Merge method", selection: $settings.mergeMethod) {
                Text("Squash").tag(MergeMethod.squash)
                Text("Merge commit").tag(MergeMethod.merge)
                Text("Rebase").tag(MergeMethod.rebase)
            }
            .pickerStyle(.segmented)
            caption("Squash keeps the PR title as the commit message, which is what semantic-release reads to pick the next version. A repository that doesn't allow this method uses its own default.")

            Toggle("Ask before clearing or merging", isOn: $settings.confirmActions)
            caption("Off, one click acts. On, the button asks \"Sure?\" and a second click confirms.")
        }
    }

    private var repositories: some View {
        Section("Repositories") {
            Stepper("Active in the last \(settings.discoveryDays) days", value: $settings.discoveryDays, in: 7...365, step: 7)
            Stepper("Watch at most \(settings.repoLimit)", value: $settings.repoLimit, in: 1...50)

            if !model.repos.isEmpty {
                repoList(model.repos.map(\.id)) { repo in
                    if settings.pinnedRepos.contains(repo) {
                        rowButton("Unpin") { settings.unpin(repo); rediscoverNow() }
                    }
                    rowButton("Ignore") { settings.setExcluded(true, repo); rediscoverNow() }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    TextField("owner/name", text: $repoToPin)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .labelsHidden()
                        .onSubmit(pin)
                    Button("Pin", action: pin)
                        .controlSize(.small)
                        .disabled(repoToPin.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                caption(pinRejected
                    ? "That isn't an owner/name."
                    : "Pin a repository to watch it however long it has been quiet.")
            }

            let ignored = settings.excludedRepos.sorted()
            if !ignored.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ignored").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    repoList(ignored) { repo in
                        rowButton("Watch again") { settings.setExcluded(false, repo); rediscoverNow() }
                    }
                }
            }

            Button("Rediscover now", action: rediscoverNow)
                .controlSize(.small)
        }
    }

    private var account: some View {
        Section("Account") {
            if let rate = model.rateLimit {
                LabeledContent("Rate limit") {
                    Text("\(rate.remaining) of \(rate.limit)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(rate.isLow ? Theme.hold : .secondary)
                }
            }
            if let warning = model.scopeWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.hold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Disconnect and forget token") {
                model.signOut()
                dismiss()
            }
            .foregroundStyle(Theme.stop)
            .controlSize(.small)
        }
    }

    // MARK: - Pieces

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func rowButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
    }

    private func repoList<Trailing: View>(
        _ repos: [String],
        @ViewBuilder trailing: @escaping (String) -> Trailing
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(repos, id: \.self) { repo in
                    HStack(spacing: 8) {
                        if settings.pinnedRepos.contains(repo) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Pinned")
                        }
                        Text(repo)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        trailing(repo)
                    }
                }
            }
        }
        .frame(maxHeight: 96)
    }

    // MARK: - Actions

    private func setLaunchAtLogin(_ wanted: Bool) {
        do {
            try LoginItem.setEnabled(wanted)
            loginItemError = nil
        } catch {
            loginItemError = "Couldn't change the login item. \(error.localizedDescription)"
        }
        // Read back rather than trust the switch: the system has the last word.
        launchAtLogin = LoginItem.isEnabled
    }

    private func pin() {
        pinRejected = !settings.pin(repoToPin)
        guard !pinRejected else { return }
        repoToPin = ""
        rediscoverNow()
    }

    private func rediscoverNow() {
        rediscovery?.cancel()
        rediscovery = Task { await model.rediscover() }
    }

    /// A stepper fires on every click. Wait for the clicking to stop before
    /// asking GitHub, rather than once per step.
    private func scheduleRediscovery() {
        rediscovery?.cancel()
        rediscovery = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await model.rediscover()
        }
    }
}
