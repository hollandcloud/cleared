import SwiftUI

/// Starts a workflow by hand. The ref defaults to main because that is what a
/// manual production deploy almost always targets.
struct DispatchSheet: View {
    let model: AppModel
    let repo: RepoRef

    @Environment(\.dismiss) private var dismiss
    @State private var selected: DispatchableWorkflow?
    @State private var ref = "main"
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Start a workflow").font(.system(size: 13, weight: .semibold))
                Text(repo.fullName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("Reading workflows…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else if model.workflows.isEmpty {
                Text("No active workflows in this repository.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(model.workflows) { workflow in
                            Button {
                                selected = workflow
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: selected?.id == workflow.id ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(selected?.id == workflow.id ? Theme.hold : .secondary)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(workflow.name).font(.system(size: 11)).lineLimit(1)
                                        Text(workflow.path)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 3)
                                .padding(.horizontal, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 190)

                HStack(spacing: 6) {
                    Text("Ref").font(.system(size: 11))
                    TextField("main", text: $ref)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                }
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Run") {
                    if let selected {
                        Task {
                            await model.dispatch(selected, ref: ref, inputs: [:])
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.hold)
                .disabled(selected == nil || ref.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 380)
        .task {
            await model.loadWorkflows(for: repo)
            isLoading = false
        }
    }
}
