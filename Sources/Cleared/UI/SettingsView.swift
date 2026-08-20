import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = Settings.shared
    @State private var pollSeconds: Double = Settings.shared.approvalInterval

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
                Section("Checking") {
                    VStack(alignment: .leading, spacing: 2) {
                        Slider(value: $pollSeconds, in: 10...300, step: 10) {
                            Text("Every \(Int(pollSeconds))s")
                        }
                        .onChange(of: pollSeconds) { _, new in settings.approvalInterval = new }
                        Text("Slows to every \(Int(pollSeconds) * settings.backgroundMultiplier)s while the menu is closed. Unchanged repositories answer from cache and cost nothing.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Toggle("Notify when something starts holding", isOn: $settings.notifyOnHold)
                    Toggle("Notify on failed runs", isOn: $settings.notifyOnFailure)
                    Toggle("Show failed runs in the queue", isOn: $settings.showFailures)
                }

                Section("Merging") {
                    Picker("Method", selection: $settings.mergeMethod) {
                        Text("Squash").tag("squash")
                        Text("Merge commit").tag("merge")
                        Text("Rebase").tag("rebase")
                    }
                    .pickerStyle(.segmented)
                    Text("Squash keeps the PR title as the commit message, which is what semantic-release reads to pick the next version.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Repositories") {
                    Stepper("Active in the last \(settings.discoveryDays) days", value: $settings.discoveryDays, in: 7...365, step: 7)
                    Stepper("Watch at most \(settings.repoLimit)", value: $settings.repoLimit, in: 1...50)
                    Button("Rediscover now") {
                        Task { try? await model.discoverRepos() }
                    }
                    .controlSize(.small)

                    if !model.repos.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(model.repos) { repo in
                                    HStack {
                                        Text(repo.fullName)
                                            .font(.system(size: 10, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                        Button("Ignore") {
                                            settings.toggleExclusion(repo)
                                            Task { try? await model.discoverRepos() }
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 96)
                    }
                }

                Section("Account") {
                    if let rate = model.rateLimit {
                        LabeledContent("Rate limit") {
                            Text("\(rate.remaining) of \(rate.limit)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(rate.isLow ? Theme.hold : .secondary)
                        }
                    }
                    Button("Disconnect and forget token") {
                        model.signOut()
                        dismiss()
                    }
                    .foregroundStyle(Theme.stop)
                    .controlSize(.small)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 400, height: 560)
    }
}
