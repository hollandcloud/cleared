import Testing
@testable import Cleared

@Suite("Workflow files")
struct WorkflowFileTests {
    @Test("the ways a workflow can declare a manual trigger", arguments: [
        "on: workflow_dispatch",
        "on: [push, workflow_dispatch]",
        "on:\n  - push\n  - workflow_dispatch",
        "on:\n- push\n- workflow_dispatch",
        "on:\n  push:\n    branches: [main]\n  workflow_dispatch:",
        "on:\n  workflow_dispatch: {}",
        "\"on\":\n  workflow_dispatch:",
        "'on':\n  workflow_dispatch:",
        "name: Deploy   # by hand\non: # triggers\n  workflow_dispatch:   # manual\njobs:\n  go:\n    runs-on: ubuntu-latest",
        "on: { workflow_dispatch: {}, push: { branches: [main] } }",
    ])
    func recognisesDispatch(yaml: String) {
        #expect(WorkflowFile.dispatchInputs(in: yaml) == [])
    }

    @Test("workflows that cannot be started by hand", arguments: [
        "on: push",
        "on: [push, pull_request]",
        "on:\n  push:\n    branches: [main]\n  schedule:\n    - cron: '0 6 * * *'",
        "name: No triggers at all",
        // Mentioned, but not as a trigger.
        "on: push\njobs:\n  go:\n    steps:\n      - run: echo workflow_dispatch",
        "on:\n  push:\n    paths: ['workflow_dispatch/**']",
        "",
    ])
    func rejectsOthers(yaml: String) {
        #expect(WorkflowFile.dispatchInputs(in: yaml) == nil)
    }

    @Test("reads each input's type, default and whether it is required")
    func readsInputs() throws {
        let yaml = """
        name: Deploy
        on:
          push:
            branches: [main]
          workflow_dispatch:
            inputs:
              environment:
                description: 'Where to deploy: staging or production'
                required: true
                default: staging
                type: choice
                options:
                  - staging
                  - production
              dry_run:
                description: "Plan only"
                type: boolean
                default: true
              version:
                description: Tag to ship   # e.g. v1.2.3
              replicas:
                type: number
                default: 3
              target:
                type: environment
                required: false
        jobs:
          deploy:
            runs-on: ubuntu-latest
            steps:
              - run: echo "inputs: ${{ inputs.environment }}"
        """

        let inputs = try #require(WorkflowFile.dispatchInputs(in: yaml))

        #expect(inputs.map(\.name) == ["environment", "dry_run", "version", "replicas", "target"])
        #expect(inputs[0] == WorkflowInput(
            name: "environment",
            description: "Where to deploy: staging or production",
            kind: .choice(["staging", "production"]),
            isRequired: true,
            defaultValue: "staging"
        ))
        #expect(inputs[1].kind == .boolean)
        #expect(inputs[1].defaultValue == "true")
        #expect(inputs[2] == WorkflowInput(name: "version", description: "Tag to ship", kind: .string, isRequired: false, defaultValue: ""))
        #expect(inputs[3].kind == .number)
        #expect(inputs[3].defaultValue == "3")
        #expect(inputs[4].kind == .environment)
    }

    @Test("copes with the looser layouts YAML allows")
    func tolerantLayouts() throws {
        let yaml = """
        on:
            workflow_dispatch:
                inputs:
                    level:
                        type: choice
                        options:
                        - info
                        - "debug"
                    regions:
                        type: choice
                        options: [us, eu]
                    notes:
                        description: >
                          Free text shown
                          on the run
                        default: "has: colon and # hash"
        """

        let inputs = try #require(WorkflowFile.dispatchInputs(in: yaml))

        #expect(inputs[0].kind == .choice(["info", "debug"]))
        #expect(inputs[1].kind == .choice(["us", "eu"]))
        #expect(inputs[2].description == "Free text shown on the run")
        #expect(inputs[2].defaultValue == "has: colon and # hash")
    }

    @Test("a choice with no options falls back to free text rather than an empty picker")
    func choiceWithoutOptions() throws {
        let yaml = "on:\n  workflow_dispatch:\n    inputs:\n      level:\n        type: choice\n"
        #expect(try #require(WorkflowFile.dispatchInputs(in: yaml)).first?.kind == .string)
    }
}
