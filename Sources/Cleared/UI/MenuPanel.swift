import SwiftUI

/// The panel. Ordered by what blocks you: held deployments, then merges that
/// are ready, then failures worth a re-run. Repositories are a label, not a
/// hierarchy — grouping by repo would bury the one item that matters.
struct MenuPanel: View {
    @Bindable var model: AppModel
    @State private var showingSettings = false
    @State private var dispatchTarget: RepoRef?
    @State private var queueHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .needsToken:
                ConnectView(model: model)
            case .connecting:
                loading
            case .failed(let message):
                FailureView(message: message, model: model)
            case .ready:
                queue
            }
        }
        .frame(width: Theme.panelWidth)
        .onAppear { model.menuIsOpen = true }
        .onDisappear { model.menuIsOpen = false }
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: model)
        }
        .sheet(item: $dispatchTarget) { repo in
            DispatchSheet(model: model, repo: repo)
        }
    }

    private var loading: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Connecting to GitHub…").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    @ViewBuilder
    private var queue: some View {
        if let banner = model.banner {
            BannerView(banner: banner) { model.banner = nil }
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if model.isAllClear && model.failures.isEmpty {
                    allClear
                }

                if !model.approvals.isEmpty {
                    SectionHeader(title: "Holding", count: model.approvals.count, tint: Theme.hold)
                    ForEach(model.approvals) { approval in
                        ActionRow(
                            dot: Theme.hold,
                            title: "\(approval.repo.name) · \(approval.runName)",
                            subtitle: "\(approval.environmentNames) · \(approval.branch) · held \(approval.waitingSince.heldDuration)",
                            isBusy: model.isBusy(approval.id),
                            openURL: approval.htmlURL
                        ) {
                            ClearButton(label: "Clear", tint: Theme.hold) {
                                Task { await model.clear(approval) }
                            }
                        }
                    }
                }

                if !model.readyToMerge.isEmpty {
                    SectionHeader(title: "Ready to merge", count: model.readyToMerge.count, tint: Theme.go)
                    ForEach(Array(model.readyToMerge.enumerated()), id: \.element.id) { index, pr in
                        ActionRow(
                            dot: Theme.go,
                            title: "#\(pr.number) \(pr.title)",
                            subtitle: "\(pr.repo.fullName) · \(pr.branch)",
                            isBusy: model.isBusy(pr.id),
                            openURL: pr.htmlURL
                        ) {
                            ClearButton(label: "Merge", tint: Theme.go) {
                                Task { await model.merge(pr) }
                            }
                        }
                        .keyboardShortcut(shortcut(for: index), modifiers: .command)
                    }
                }

                if !model.blockedPullRequests.isEmpty {
                    SectionHeader(title: "In flight", count: model.blockedPullRequests.count, tint: .secondary)
                    ForEach(model.blockedPullRequests) { pr in
                        ActionRow(
                            dot: pr.checkState == .failure ? Theme.stop : .secondary.opacity(0.5),
                            title: "#\(pr.number) \(pr.title)",
                            subtitle: "\(pr.repo.name) · \(pr.blockReason ?? "waiting")",
                            isBusy: false,
                            openURL: pr.htmlURL
                        ) { EmptyView() }
                    }
                }

                if !model.failures.isEmpty {
                    SectionHeader(title: "Failed", count: model.failures.count, tint: Theme.stop)
                    ForEach(model.failures) { run in
                        ActionRow(
                            dot: Theme.stop,
                            title: "\(run.repo.name) · \(run.name)",
                            subtitle: "\(run.branch) · \(run.finishedAt.heldDuration) ago",
                            isBusy: model.isBusy(run.id),
                            openURL: run.htmlURL
                        ) {
                            Button("Re-run") { Task { await model.rerun(run) } }
                                .font(.system(size: 11))
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .frame(width: 52)
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .measureHeight()
        }
        // Grow with the queue, stop at maxQueueHeight, scroll past that.
        .frame(height: min(max(queueHeight, 1), Theme.maxQueueHeight))
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(ContentHeightKey.self) { height in
            queueHeight = height
        }

        Divider()
        footer
    }

    private var allClear: some View {
        VStack(spacing: 5) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.go)
            Text("All clear")
                .font(.system(size: 13, weight: .medium))
            Text("Nothing is waiting on you.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.isRefreshing {
                ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
            } else {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Refresh now")
            }

            Text(statusLine)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Menu {
                ForEach(model.repos) { repo in
                    Button(repo.fullName) { dispatchTarget = repo }
                }
            } label: {
                Image(systemName: "play.circle").font(.system(size: 10))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Start a workflow")

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .help("Quit Cleared")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var statusLine: String {
        var parts: [String] = []
        if let last = model.lastRefresh { parts.append("checked \(last.heldDuration) ago") }
        if let rate = model.rateLimit {
            parts.append("\(rate.remaining) calls left")
        }
        parts.append("\(model.repos.count) repos")
        return parts.joined(separator: " · ")
    }

    /// ⌘1–⌘9 on the merge queue, in the order shown.
    private func shortcut(for index: Int) -> KeyEquivalent {
        guard index < 9, let scalar = Unicode.Scalar(UInt32(49 + index)) else { return .return }
        return KeyEquivalent(Character(scalar))
    }
}

struct SectionHeader: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(tint)
            Text("\(count)")
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 3)
    }
}

struct BannerView: View {
    let banner: AppModel.Banner
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: banner.kind == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(banner.kind == .success ? Theme.go : Theme.stop)
            Text(banner.text)
                .font(.system(size: 11))
                .lineLimit(2)
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 8)) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((banner.kind == .success ? Theme.go : Theme.stop).opacity(0.12))
        .task {
            try? await Task.sleep(for: .seconds(4))
            dismiss()
        }
    }
}
