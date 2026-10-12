import SwiftUI

/// The panel. Ordered by what blocks you: held deployments, then merges that
/// are ready, then failures worth a re-run. Repositories are a label, not a
/// hierarchy — grouping by repo would bury the one item that matters.
struct MenuPanel: View {
    @Bindable var model: AppModel
    @State private var showingSettings = false
    @State private var dispatchTarget: RepoRef?
    @State private var rejectTarget: PendingApproval?
    @State private var queueHeight: CGFloat = 0

    private var settings: Settings { Settings.shared }

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
        // Two signals for the same fact. SwiftUI's appear/disappear is the
        // obvious one, but a menu bar panel is hidden rather than torn down,
        // so the window's own visibility is watched as well.
        .onAppear { model.panelDidOpen() }
        .onDisappear { model.panelDidClose() }
        .background(WindowVisibility { visible in
            if visible { model.panelDidOpen() } else { model.panelDidClose() }
        })
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: model)
        }
        .sheet(item: $dispatchTarget) { repo in
            DispatchSheet(model: model, repo: repo)
        }
        .sheet(item: $rejectTarget) { approval in
            RejectSheet(model: model, approval: approval)
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
            // "held 6m" and "checked 40s ago" are only true for a moment, so
            // the rows are redrawn on a timer rather than only when data lands.
            TimelineView(.periodic(from: .now, by: 20)) { _ in
                rows
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
        TimelineView(.periodic(from: .now, by: 20)) { _ in
            footer
        }
    }

    private var rows: some View {
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
                        openURL: approval.htmlURL,
                        actions: [RowAction(title: "Reject…", isDestructive: true) { rejectTarget = approval }]
                    ) {
                        ClearButton(label: "Clear", tint: Theme.hold, confirms: settings.confirmActions) {
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
                        ClearButton(
                            label: "Merge",
                            tint: Theme.go,
                            confirms: settings.confirmActions,
                            shortcut: shortcut(for: index)
                        ) {
                            Task { await model.merge(pr) }
                        }
                    }
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
        .accessibilityElement(children: .combine)
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
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh now (⌘R)")
                .accessibilityLabel("Refresh now")
            }

            Text(statusLine)
                .font(.system(size: 10))
                .foregroundStyle(model.pollProblem == nil ? Color.secondary : Theme.hold)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(statusLine)

            Spacer()

            Menu {
                ForEach(model.repos) { repo in
                    Button(repo.fullName) { dispatchTarget = repo }
                }
            } label: {
                // A Label rather than a bare Image: the menu takes its spoken
                // name from here, and an image alone announces as "play".
                Label("Start a workflow", systemImage: "play.circle")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 10))
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
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit Cleared (⌘Q)")
            .accessibilityLabel("Quit Cleared")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    /// When a poll came back short the footer says why, and how stale the
    /// queue above it is — that is the only thing worth knowing at that point.
    private var statusLine: String {
        var parts: [String] = []
        if let problem = model.pollProblem {
            parts.append(problem)
            if let last = model.lastRefresh { parts.append("last checked \(last.heldDuration) ago") }
            return parts.joined(separator: " · ")
        }
        if let last = model.lastRefresh { parts.append("checked \(last.heldDuration) ago") }
        if let rate = model.rateLimit {
            parts.append("\(rate.remaining) calls left")
        }
        parts.append("\(model.repos.count) repos")
        return parts.joined(separator: " · ")
    }

    /// ⌘1–⌘9 on the merge queue, in the order shown. Rows past the ninth have
    /// no shortcut.
    private func shortcut(for index: Int) -> KeyEquivalent? {
        guard index < 9, let scalar = Unicode.Scalar(UInt32(49 + index)) else { return nil }
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(title), \(count)")
    }
}

struct BannerView: View {
    let banner: AppModel.Banner
    let dismiss: () -> Void

    @Environment(\.openURL) private var open

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: banner.kind == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(banner.kind == .success ? Theme.go : Theme.stop)
            Text(banner.text)
                .font(.system(size: 11))
                .lineLimit(2)
            Spacer()
            if let link = banner.link {
                Button("Open") { open(link) }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 8)) }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((banner.kind == .success ? Theme.go : Theme.stop).opacity(0.12))
        // Keyed on the banner: a second banner arriving restarts the clock
        // instead of inheriting what was left of the first one's.
        .task(id: banner.id) {
            // A failure, or a result with a link to follow, stays up longer.
            let seconds: Double = banner.kind == .failure || banner.link != nil ? 8 : 4
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { dismiss() }
        }
    }
}

/// Turns a held deployment down. GitHub requires a comment, and the people
/// whose deploy just got cancelled deserve one.
struct RejectSheet: View {
    let model: AppModel
    let approval: PendingApproval

    @Environment(\.dismiss) private var dismiss
    @State private var comment = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reject this deployment?").font(.system(size: 13, weight: .semibold))
                Text("\(approval.repo.fullName) · \(approval.runName)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("The jobs waiting on \(approval.environmentNames) will be cancelled. This can't be undone from here — the workflow has to be run again.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Why (shown on the run)", text: $comment, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .lineLimit(2...4)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Reject", role: .destructive) {
                    let reason = comment
                    dismiss()
                    Task { await model.reject(approval, comment: reason) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.stop)
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}
