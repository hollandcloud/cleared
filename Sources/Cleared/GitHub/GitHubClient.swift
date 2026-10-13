import Foundation

enum GitHubError: Error, LocalizedError, Sendable, Equatable {
    case notAuthenticated
    case http(status: Int, message: String)
    /// GitHub asked Cleared to stop for a while. `until` is when it may resume.
    case rateLimited(until: Date)
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Connect Cleared to GitHub first."
        case .http(let status, let message):
            switch status {
            case 401: return "GitHub rejected the token. Reconnect in Settings."
            case 403:
                if message.localizedCaseInsensitiveContains("rate limit") {
                    return "Rate limited. Cleared will back off and retry."
                }
                if message.localizedCaseInsensitiveContains("SAML") {
                    return "That organization requires single sign-on. Authorize the token for it on GitHub."
                }
                return "That token lacks permission. It needs the repo scope."
            case 404: return "Not found — the token may not have access to that repository."
            case 405, 409, 422: return message
            default: return "GitHub returned \(status). \(message)"
            }
        case .rateLimited(let until):
            let minutes = max(1, Int((until.timeIntervalSinceNow / 60).rounded(.up)))
            return "Rate limited. Cleared will retry in \(minutes)m."
        case .transport(let detail):
            return "Couldn't reach GitHub. \(detail)"
        case .decoding(let detail):
            return "Unexpected response from GitHub. \(detail)"
        }
    }

    var isUnauthorized: Bool {
        if case .http(status: 401, _) = self { return true }
        return false
    }
}

/// Talks to GitHub. Actor-isolated so the ETag cache and rate-limit reading
/// stay consistent while several polls run concurrently.
///
/// The ETag cache is what makes a 30-second poll across many repositories
/// affordable: GitHub does not charge a 304 against the hourly limit, and the
/// "nothing is waiting" response for a quiet repository is byte-identical every
/// time, so a quiet repository costs nothing at all.
actor GitHubClient {
    private let session: URLSession
    private let token: @Sendable () -> String?
    private let now: @Sendable () -> Date
    private var cache: [String: (etag: String, data: Data)] = [:]
    /// REST and GraphQL draw on separate budgets, so they are tracked apart.
    private var rateLimits: [String: RateLimit] = [:]
    private var blockedUntil: [String: Date] = [:]

    private enum Resource {
        static let core = "core"
        static let graphQL = "graphql"
    }

    init(
        session: URLSession? = nil,
        token: @escaping @Sendable () -> String? = { TokenStore.current() },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.token = token
        self.now = now
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20
            config.waitsForConnectivity = false
            config.httpAdditionalHeaders = [
                "User-Agent": "Cleared/\(AppEnvironment.version) (+https://github.com/hollandcloud/cleared)",
            ]
            self.session = URLSession(configuration: config)
        }
    }

    /// The REST budget — the one polling spends, and the one worth showing.
    func currentRateLimit() -> RateLimit? { rateLimits[Resource.core] }

    func clearCache() {
        cache.removeAll()
        rateLimits.removeAll()
        blockedUntil.removeAll()
    }

    // MARK: - REST

    struct Response: Sendable {
        let data: Data
        let status: Int
        /// True when GitHub answered 304 and this is the previously cached body.
        let notModified: Bool
        /// The scopes a classic token carries. Nil for fine-grained tokens,
        /// which do not report any.
        let scopes: [String]?
    }

    /// Issues a REST request, reusing an ETag when one is known for this path.
    @discardableResult
    func rest(
        _ method: String,
        _ path: String,
        body: (any Encodable & Sendable)? = nil,
        useCache: Bool = false
    ) async throws -> Response {
        guard let token = token() else { throw GitHubError.notAuthenticated }
        guard let url = URL(string: "https://api.github.com/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            throw GitHubError.transport("Bad URL for \(path)")
        }

        // Once GitHub has said stop, keep asking nothing until it said to
        // resume. Retrying into a secondary limit is how a token gets flagged.
        let resource = path == "graphql" ? Resource.graphQL : Resource.core
        if let until = blockedUntil[resource] {
            if until > now() { throw GitHubError.rateLimited(until: until) }
            blockedUntil[resource] = nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let cacheKey = "\(method) \(path)"
        if useCache, let cached = cache[cacheKey] {
            request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match")
        }

        if let body {
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GitHubError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.transport("Malformed response")
        }

        readRateLimit(from: http, fallbackResource: resource)
        let scopes = http.value(forHTTPHeaderField: "X-OAuth-Scopes").map { header in
            header.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        if http.statusCode == 304, let cached = cache[cacheKey] {
            return Response(data: cached.data, status: 304, notModified: true, scopes: scopes)
        }

        if let until = rateLimitRelease(from: http, data: data) {
            blockedUntil[resource] = until
            Log.github.notice("rate limited on \(resource, privacy: .public); resuming in \(Int(until.timeIntervalSince(self.now())))s")
            throw GitHubError.rateLimited(until: until)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw GitHubError.http(status: http.statusCode, message: Self.message(from: data))
        }

        if useCache, let etag = http.value(forHTTPHeaderField: "ETag") {
            cache[cacheKey] = (etag, data)
        }

        return Response(data: data, status: http.statusCode, notModified: false, scopes: scopes)
    }

    func get<T: Decodable & Sendable>(_ type: T.Type, _ path: String, useCache: Bool = false) async throws -> T {
        let response = try await rest("GET", path, useCache: useCache)
        return try Self.decode(type, from: response.data)
    }

    // MARK: - GraphQL

    /// One request covers every open pull request across every repository, which
    /// is why the merge lane costs a single call no matter how many repos exist.
    func graphQL<T: Decodable & Sendable>(
        _ type: T.Type,
        query: String,
        variables: [String: String]
    ) async throws -> T {
        let response = try await rest("POST", "graphql", body: GraphQLBody(query: query, variables: variables))

        let envelope = try Self.decode(GraphQLEnvelope<T>.self, from: response.data)
        if let errors = envelope.errors, !errors.isEmpty {
            throw GitHubError.http(status: 200, message: errors.map(\GraphQLEnvelope<T>.GQLError.message).joined(separator: "; "))
        }
        guard let payload = envelope.data else {
            throw GitHubError.decoding("GraphQL returned no data")
        }
        return payload
    }

    // MARK: - Helpers

    private func readRateLimit(from http: HTTPURLResponse, fallbackResource: String) {
        guard let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init),
              let limit = http.value(forHTTPHeaderField: "X-RateLimit-Limit").flatMap(Int.init),
              let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init)
        else { return }
        let resource = http.value(forHTTPHeaderField: "X-RateLimit-Resource") ?? fallbackResource
        rateLimits[resource] = RateLimit(remaining: remaining, limit: limit, resetsAt: Date(timeIntervalSince1970: reset))
    }

    /// When GitHub is rate limiting this response, the moment it is safe to
    /// try again; nil for every other response.
    ///
    /// A primary limit arrives as 403 or 429 with no budget remaining. A
    /// secondary limit arrives as 403 or 429 with `Retry-After`, or with
    /// neither header and only the message to go on.
    private func rateLimitRelease(from http: HTTPURLResponse, data: Data) -> Date? {
        guard http.statusCode == 403 || http.statusCode == 429 else { return nil }

        if let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) {
            return now().addingTimeInterval(max(1, retryAfter))
        }
        if http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0",
           let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init) {
            return max(Date(timeIntervalSince1970: reset), now().addingTimeInterval(1))
        }
        if http.statusCode == 429 || Self.message(from: data).localizedCaseInsensitiveContains("rate limit") {
            // GitHub's guidance when it gives no number: wait at least a minute.
            return now().addingTimeInterval(60)
        }
        return nil
    }

    nonisolated static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw GitHubError.decoding(String(describing: error))
        }
    }

    nonisolated static func message(from data: Data) -> String {
        struct APIError: Decodable { let message: String? }
        if let parsed = try? JSONDecoder().decode(APIError.self, from: data), let message = parsed.message {
            return message
        }
        return String(decoding: data.prefix(200), as: UTF8.self)
    }
}

private struct GraphQLBody: Encodable, Sendable {
    let query: String
    let variables: [String: String]
}

private struct GraphQLEnvelope<Payload: Decodable>: Decodable {
    struct GQLError: Decodable { let message: String }
    let data: Payload?
    let errors: [GQLError]?
}

/// Lets `rest(_:_:body:)` accept any Encodable without making the whole client generic.
private struct AnyEncodable: Encodable {
    private let encode: @Sendable (Encoder) throws -> Void
    init(_ wrapped: any Encodable & Sendable) {
        encode = { encoder in try wrapped.encode(to: encoder) }
    }
    func encode(to encoder: Encoder) throws { try encode(encoder) }
}
