import Testing
import Foundation
@testable import Cleared

/// Settings backed by a throwaway defaults domain, so a test never reads or
/// writes the preferences of the person running it.
@MainActor
final class ScratchSettings {
    let settings: Settings
    private let domain = "ClearedTests.\(UUID().uuidString)"

    init() {
        settings = Settings(defaults: UserDefaults(suiteName: domain)!)
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }
}

/// Holds a token in memory. Every model a test builds gets one of these, so
/// nothing in the suite can read, replace or delete a real Keychain entry.
final class MemoryVault: @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    init(_ token: String? = nil) {
        self.token = token
    }

    var current: String? { lock.withLock { token } }

    var vault: TokenVault {
        TokenVault(
            current: { [self] in lock.withLock { token } },
            save: { [self] new in lock.withLock { token = new } },
            clear: { [self] in lock.withLock { token = nil } }
        )
    }
}

private func stamp(daysAgo: Double) -> String {
    ISO8601DateFormatter().string(from: Date().addingTimeInterval(-daysAgo * 86_400))
}

/// A GitHub with two repositories, one deployment held in `web`, and one green
/// pull request. Individual tests override the parts they care about.
private func everydayGitHub(_ request: StubGitHub.Request) -> StubGitHub.Reply {
    switch request.path {
    case "/user":
        return .json(#"{"login": "octocat"}"#, headers: ["X-OAuth-Scopes": "repo"])
    case "/graphql":
        return .json(Fixture.search([Fixture.pullRequest(number: 7)]))
    case let path where path.hasPrefix("/user/repos"):
        return .json(Fixture.repos(["web", "api"], pushedAt: stamp(daysAgo: 1)))
    case let path where path.contains("pending_deployments"):
        return .json(Fixture.pendingDeployments([(11, "production", true)]))
    case let path where path.contains("/acme/web/actions/runs?status=waiting"):
        return .json(Fixture.runs([42], updatedAt: stamp(daysAgo: 0.01)))
    default:
        return .json(Fixture.runs([]))
    }
}

@MainActor
@Suite("App model")
struct AppModelTests {
    private let github = StubGitHub()
    private let scratch = ScratchSettings()
    private let memory = MemoryVault("saved-token")

    private func makeModel() -> AppModel {
        AppModel(client: github.client(), settings: scratch.settings, vault: memory.vault)
    }

    private func connectedModel() async -> AppModel {
        github.respond(everydayGitHub)
        let model = makeModel()
        await model.connect()
        return model
    }

    @Test("connecting fills the queue")
    func connects() async {
        let model = await connectedModel()

        #expect(model.phase == .ready)
        #expect(model.login == "octocat")
        #expect(model.repos.map(\.id) == ["acme/web", "acme/api"])
        #expect(model.approvals.map(\.id) == ["acme/web#42"])
        #expect(model.readyToMerge.map(\.number) == [7])
        #expect(model.pendingCount == 2)
        #expect(model.pollProblem == nil)
        #expect(model.scopeWarning == nil)
    }

    @Test("a token GitHub rejects goes back to the connect screen and says why")
    func rejectedToken() async {
        github.respond { _ in .json(#"{"message": "Bad credentials"}"#, status: 401) }
        let model = makeModel()

        await model.connect()

        #expect(model.phase == .needsToken)
        #expect(model.connectNotice?.contains("rejected") == true)
    }

    @Test("a token revoked mid-session empties the queue instead of polling on")
    func revokedMidSession() async {
        let model = await connectedModel()
        github.respond { _ in .json(#"{"message": "Bad credentials"}"#, status: 401) }

        await model.refresh()

        #expect(model.phase == .needsToken)
        #expect(model.approvals.isEmpty)
        #expect(model.pullRequests.isEmpty)
        #expect(model.connectNotice != nil)
    }

    @Test("a read-only token connects but warns that actions will be refused")
    func readOnlyToken() async {
        github.respond { request in
            request.path == "/user"
                ? .json(#"{"login": "octocat"}"#, headers: ["X-OAuth-Scopes": "read:org"])
                : everydayGitHub(request)
        }
        let model = makeModel()

        await model.connect()

        #expect(model.phase == .ready)
        #expect(model.scopeWarning?.contains("repo scope") == true)
    }

    @Test("offline keeps the last queue on screen and stops asking after the first failure")
    func offline() async {
        let model = await connectedModel()
        let before = github.requests(matching: "status=waiting").count
        github.respond { _ in .offline }

        await model.refresh()

        #expect(model.phase == .ready)
        #expect(model.approvals.map(\.id) == ["acme/web#42"])
        #expect(model.readyToMerge.count == 1)
        #expect(model.pollProblem?.contains("Couldn't reach GitHub") == true)
        // Two repositories are watched; the second is not tried once the first times out.
        #expect(github.requests(matching: "status=waiting").count == before + 1)
    }

    @Test("a problem clears itself once GitHub answers again")
    func recovers() async {
        let model = await connectedModel()
        github.respond { _ in .offline }
        await model.refresh()
        github.respond(everydayGitHub)

        await model.refresh()

        #expect(model.pollProblem == nil)
    }

    @Test("a repository that refuses Actions access is not asked again every poll")
    func skipsUnreadableRepos() async {
        github.respond { request in
            request.path.contains("/acme/api/actions/runs")
                ? .json(#"{"message": "Not Found"}"#, status: 404)
                : everydayGitHub(request)
        }
        let model = makeModel()
        await model.connect()

        await model.refresh()
        await model.refresh()

        #expect(github.requests(matching: "/acme/api/actions/runs?status=waiting").count == 1)
        #expect(model.approvals.count == 1)
        #expect(model.pollProblem == nil)
    }

    @Test("clearing approves the deployment and takes it off the queue")
    func clears() async throws {
        let model = await connectedModel()
        let hold = try #require(model.approvals.first)

        await model.clear(hold)

        #expect(model.approvals.isEmpty)
        #expect(model.banner?.kind == .success)
        let sent = try #require(github.requests.last { $0.method == "POST" && $0.path.contains("pending_deployments") })
        #expect(sent.json["state"] as? String == "approved")
        #expect(sent.json["environment_ids"] as? [Int] == [11])
    }

    @Test("a refused action leaves the item in place and shows GitHub's reason")
    func failedActionKeepsItem() async throws {
        let model = await connectedModel()
        let pr = try #require(model.readyToMerge.first)
        github.respond { request in
            request.method == "PUT"
                ? .json(#"{"message": "Head branch was modified. Review and try the merge again."}"#, status: 409)
                : everydayGitHub(request)
        }

        await model.merge(pr)

        #expect(model.readyToMerge.count == 1)
        #expect(model.banner?.kind == .failure)
        #expect(model.banner?.text.contains("Head branch was modified") == true)
    }

    @Test("a notification's Clear button does nothing for a hold that is already gone")
    func staleNotification() async {
        let model = await connectedModel()

        await model.clearHold(withID: "acme/web#999")

        #expect(model.banner?.kind == .failure)
        #expect(!github.requests.contains { $0.method == "POST" && $0.path.contains("pending_deployments") })
        #expect(model.approvals.count == 1)
    }

    @Test("merging falls back to a method the repository allows")
    func mergeMethodFallback() async throws {
        scratch.settings.mergeMethod = .rebase
        github.respond { request in
            switch (request.method, request.path) {
            case ("POST", "/graphql"):
                return .json(Fixture.search([Fixture.pullRequest(number: 7, mergeCommit: false, rebase: false)]))
            case ("PUT", _):
                return .json(#"{"merged": true}"#)
            default:
                return everydayGitHub(request)
            }
        }
        let model = makeModel()
        await model.connect()
        let pr = try #require(model.readyToMerge.first)

        await model.merge(pr)

        let sent = try #require(github.requests.last { $0.method == "PUT" })
        #expect(sent.json["merge_method"] as? String == "squash")
        #expect(sent.json["sha"] as? String == "abc7")
        #expect(model.pullRequests.isEmpty)
    }

    @Test("failures too old for GitHub to re-run are not offered")
    func hidesStaleFailures() async {
        github.respond { request in
            if request.path.contains("/acme/web/actions/runs?status=failure") {
                return .json(Fixture.runs([1], updatedAt: stamp(daysAgo: 2)))
            }
            if request.path.contains("/acme/api/actions/runs?status=failure") {
                return .json(Fixture.runs([2], updatedAt: stamp(daysAgo: 45)))
            }
            return everydayGitHub(request)
        }
        let model = makeModel()

        await model.connect()

        #expect(model.failures.map(\.runID) == [1])
    }

    @Test("ignored repositories are not watched; pinned ones always are")
    func honoursPinsAndIgnores() async {
        scratch.settings.setExcluded(true, "acme/api")
        scratch.settings.pin("acme/quiet")

        let model = await connectedModel()

        #expect(model.repos.map(\.id) == ["acme/quiet", "acme/web"])
    }

    @Test("polls quickly while the panel is open and backs off when it closes")
    func cadence() async {
        let model = await connectedModel()
        #expect(model.pollDelay == 120)

        model.panelDidOpen()
        #expect(model.pollDelay == 30)

        model.panelDidClose()
        #expect(model.pollDelay == 120)
    }

    @Test("signing out forgets everything")
    func signsOut() async {
        let model = await connectedModel()

        model.signOut()

        #expect(model.phase == .needsToken)
        #expect(model.login == nil)
        #expect(model.approvals.isEmpty && model.pullRequests.isEmpty && model.repos.isEmpty)
        #expect(model.connectNotice == nil)
        #expect(memory.current == nil)
    }

    @Test("starting with a saved token connects without anyone opening the panel")
    func startsOnLaunch() async {
        github.respond(everydayGitHub)
        let model = makeModel()

        await model.start()

        #expect(model.phase == .ready)
        #expect(model.approvals.count == 1)
    }

    @Test("starting with no token waits on the connect screen and asks GitHub nothing")
    func startsWithoutToken() async {
        let model = AppModel(client: github.client(), settings: scratch.settings, vault: MemoryVault().vault)

        await model.start()

        #expect(model.phase == .needsToken)
        #expect(model.connectNotice == nil)
        #expect(github.requests.isEmpty)
    }

    @Test("pasting a token stores it and connects")
    func signsIn() async {
        github.respond(everydayGitHub)
        let empty = MemoryVault()
        let model = AppModel(client: github.client(), settings: scratch.settings, vault: empty.vault)

        await model.signIn(token: "pasted-token")

        #expect(empty.current == "pasted-token")
        #expect(model.phase == .ready)
    }
}
