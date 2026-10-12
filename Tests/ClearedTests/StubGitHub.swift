import Foundation
@testable import Cleared

/// A stand-in for api.github.com.
///
/// Each instance hands out its own token, and replies are looked up by the
/// `Authorization` header that token produces. That keeps every test's stubs
/// private to it, so the suites can run in parallel without sharing state.
final class StubGitHub: @unchecked Sendable {
    struct Reply {
        var status = 200
        var headers: [String: String] = [:]
        var body = "{}"
        var failure: URLError.Code?

        static func json(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> Reply {
            Reply(status: status, headers: headers, body: body)
        }

        static let offline = Reply(failure: .notConnectedToInternet)
    }

    struct Request {
        let method: String
        /// Path and query, e.g. `/repos/o/r/actions/runs?status=waiting&per_page=20`.
        let path: String
        let headers: [String: String]
        let body: Data

        var json: [String: Any] {
            (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        }

        /// The GraphQL query text, for telling one query from another.
        var query: String { json["query"] as? String ?? "" }
    }

    let token = "stub-\(UUID().uuidString)"
    private let lock = NSLock()
    private var handler: @Sendable (Request) -> Reply = { _ in Reply() }
    private var seen: [Request] = []
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    init() {
        StubProtocol.register(self)
    }

    deinit {
        StubProtocol.unregister(token)
    }

    /// A client wired to this stub, with a clock the test controls.
    func client(authenticated: Bool = true) -> GitHubClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let token = authenticated ? self.token : nil
        return GitHubClient(session: URLSession(configuration: config), token: { token }, now: { [weak self] in self?.now ?? Date() })
    }

    func respond(_ handler: @escaping @Sendable (Request) -> Reply) {
        lock.withLock { self.handler = handler }
    }

    var requests: [Request] { lock.withLock { seen } }

    func requests(matching fragment: String) -> [Request] {
        requests.filter { $0.path.contains(fragment) }
    }

    var now: Date { lock.withLock { clock } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { clock = clock.addingTimeInterval(seconds) }
    }

    fileprivate func reply(to request: Request) -> Reply {
        let handler = lock.withLock {
            seen.append(request)
            return self.handler
        }
        return handler(request)
    }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [String: StubGitHub] = [:]

    static func register(_ stub: StubGitHub) {
        lock.withLock { stubs["Bearer \(stub.token)"] = stub }
    }

    static func unregister(_ token: String) {
        lock.withLock { stubs["Bearer \(token)"] = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
        guard let stub = Self.lock.withLock({ Self.stubs[authorization] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired))
            return
        }

        let seen = StubGitHub.Request(
            method: request.httpMethod ?? "GET",
            path: url.path + (url.query.map { "?\($0)" } ?? ""),
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.body(of: request)
        )
        let reply = stub.reply(to: seen)

        if let failure = reply.failure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession moves a request's body into a stream before a protocol sees it.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Canned GitHub responses, trimmed to the fields Cleared reads.
enum Fixture {
    static func runs(_ ids: [Int], updatedAt: String = "2027-01-15T08:00:00Z") -> String {
        let runs = ids.map { id in
            """
            {"id": \(id), "name": "Deploy", "head_branch": "main", "status": "waiting", "conclusion": null,
             "created_at": "\(updatedAt)", "updated_at": "\(updatedAt)",
             "html_url": "https://github.com/acme/web/actions/runs/\(id)"}
            """
        }
        return #"{"total_count": \#(ids.count), "workflow_runs": [\#(runs.joined(separator: ","))]}"#
    }

    static func pendingDeployments(_ environments: [(id: Int, name: String, mine: Bool)]) -> String {
        let items = environments.map {
            #"{"environment": {"id": \#($0.id), "name": "\#($0.name)"}, "current_user_can_approve": \#($0.mine), "wait_timer": 0}"#
        }
        return "[\(items.joined(separator: ","))]"
    }

    static func repos(_ names: [String], pushedAt: String) -> String {
        let items = names.map {
            #"{"name": "\#($0)", "owner": {"login": "acme"}, "archived": false, "disabled": false, "pushed_at": "\#(pushedAt)"}"#
        }
        return "[\(items.joined(separator: ","))]"
    }

    static func pullRequest(
        number: Int,
        mergeState: String = "CLEAN",
        review: String? = nil,
        rollup: String? = "SUCCESS",
        squash: Bool = true,
        mergeCommit: Bool = true,
        rebase: Bool = true,
        defaultMethod: String = "SQUASH"
    ) -> String {
        """
        {"number": \(number), "title": "feat: thing \(number)", "url": "https://github.com/acme/web/pull/\(number)",
         "isDraft": false, "headRefName": "feat/thing", "headRefOid": "abc\(number)", "updatedAt": "2027-01-15T08:00:00Z",
         "mergeable": "MERGEABLE", "mergeStateStatus": "\(mergeState)",
         "reviewDecision": \(review.map { "\"\($0)\"" } ?? "null"), "isInMergeQueue": false,
         "repository": {"name": "web", "owner": {"login": "acme"}, "squashMergeAllowed": \(squash),
                        "mergeCommitAllowed": \(mergeCommit), "rebaseMergeAllowed": \(rebase),
                        "viewerDefaultMergeMethod": "\(defaultMethod)"},
         "commits": {"nodes": [{"commit": {"statusCheckRollup": \(rollup.map { "{\"state\": \"\($0)\"}" } ?? "null")}}]}}
        """
    }

    static func search(_ nodes: [String]) -> String {
        #"{"data": {"search": {"nodes": [\#(nodes.joined(separator: ","))]}}}"#
    }
}
