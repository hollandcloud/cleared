import SwiftUI

/// Starts a workflow by hand.
///
/// Only workflows that declare `workflow_dispatch` are listed, and each one
/// brings the inputs its file declares — so what this sheet offers is what
/// GitHub will accept, rather than a form that 422s on submit.
struct DispatchSheet: View {
    let model: AppModel
    let repo: RepoRef

    @Environment(\.dismiss) private var dismiss
    @State private var catalog: WorkflowCatalog?
    @State private var loadError: String?
    @State private var selected: DispatchableWorkflow?
    @State private var ref = ""
    @State private var values: [String: String] = [:]
    @State private var isStarting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Start a workflow").font(.system(size: 13, weight: .semibold))
                Text(repo.fullName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let catalog {
                if catalog.workflows.isEmpty {
                    Text("Nothing in this repository can be started by hand. A workflow needs `workflow_dispatch` in its `on:` block.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 12)
                } else {
                    workflowList(catalog.workflows)
                    form
                }
            } else if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("Reading workflows…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Run") { start() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.hold)
                    .disabled(!canStart)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 380)
        .task { await load() }
    }

    private func workflowList(_ workflows: [DispatchableWorkflow]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(workflows) { workflow in
                    Button {
                        select(workflow)
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
                    .accessibilityAddTraits(selected?.id == workflow.id ? .isSelected : [])
                }
            }
        }
        .frame(height: min(CGFloat(workflows.count) * 31, 155))
    }

    @ViewBuilder
    private var form: some View {
        LabeledField("Ref") {
            TextField("branch or tag", text: $ref)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .accessibilityLabel("Ref")
        }

        if let inputs = selected?.inputs, !inputs.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(inputs) { input in
                        InputField(input: input, value: binding(for: input))
                    }
                }
            }
            .frame(maxHeight: 190)
        }
    }

    private var canStart: Bool {
        guard let selected, !isStarting, !ref.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return selected.inputs.allSatisfy { !$0.isRequired || !(values[$0.name] ?? "").isEmpty }
    }

    private func binding(for input: WorkflowInput) -> Binding<String> {
        Binding(get: { values[input.name] ?? "" }, set: { values[input.name] = $0 })
    }

    private func load() async {
        do {
            let loaded = try await model.workflowCatalog(for: repo)
            catalog = loaded
            ref = loaded.defaultBranch
            if loaded.workflows.count == 1 { select(loaded.workflows[0]) }
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Seeds each input with what the workflow file declares as its default,
    /// so an untouched form sends exactly what a run from github.com would.
    private func select(_ workflow: DispatchableWorkflow) {
        selected = workflow
        values = Dictionary(uniqueKeysWithValues: workflow.inputs.map { input in
            switch input.kind {
            case .boolean:
                return (input.name, input.defaultValue.lowercased() == "true" ? "true" : "false")
            case .choice(let options):
                return (input.name, options.contains(input.defaultValue) ? input.defaultValue : (options.first ?? ""))
            case .string, .number, .environment:
                return (input.name, input.defaultValue)
            }
        })
    }

    private func start() {
        guard let selected else { return }
        isStarting = true
        // An input left empty is omitted, which lets the workflow's own
        // default apply rather than overriding it with an empty string.
        let inputs = values.filter { !$0.value.isEmpty }
        let target = ref.trimmingCharacters(in: .whitespaces)
        Task {
            await model.dispatch(selected, ref: target, inputs: inputs)
            dismiss()
        }
    }
}

private struct LabeledField<Field: View>: View {
    let label: String
    let caption: String
    let field: Field

    init(_ label: String, caption: String = "", @ViewBuilder field: () -> Field) {
        self.label = label
        self.caption = caption
        self.field = field()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11))
                    .frame(width: 96, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(label)
                field
            }
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 102)
            }
        }
    }
}

/// One declared input, drawn as the control its type calls for.
private struct InputField: View {
    let input: WorkflowInput
    @Binding var value: String

    var body: some View {
        LabeledField(input.name, caption: caption) {
            switch input.kind {
            case .boolean:
                Toggle("", isOn: Binding(get: { value == "true" }, set: { value = $0 ? "true" : "false" }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .accessibilityLabel(spokenName)
                Spacer()
            case .choice(let options):
                Picker("", selection: $value) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel(spokenName)
            case .string, .number, .environment:
                TextField(input.isRequired ? "required" : "optional", text: $value)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .accessibilityLabel(spokenName)
            }
        }
    }

    /// The visible label sits beside the control, not on it, so each control
    /// is named explicitly for VoiceOver.
    private var spokenName: String {
        input.isRequired ? "\(input.name), required" : input.name
    }

    private var caption: String {
        let needsValue = input.isRequired && value.isEmpty
        if input.description.isEmpty { return needsValue ? "Required." : "" }
        return needsValue ? "\(input.description) Required." : input.description
    }
}
