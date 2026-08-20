import Foundation

enum GitHubError: Error, LocalizedError, Sendable {
    case notAuthenticated
    case http(status: Int, message: String)
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Connect Cleared to GitHub first."
        case .http(let status, let message):
            switch status {
            case 401: return "GitHub rejected the token. Reconnect in Settings."
            case 403: return message.contains("rate limit")
                ? "Rate limited. Cleared will back off and retry."
                : "That token lacks permission. It needs the repo and workflow scopes."
            case 404: return "Not found — the token may not have access to that repository."
            case 405, 409: return message
            case 422: return message
            default: return "GitHub returned \(status). \(message)"
            }
        case .transport(let detail):
            return "Couldn't reach GitHub. \(detail)"
        case .decoding(let detail):
            return "Unexpected response from GitHub. \(detail)"
        }
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
    private var cache: [String: (etag: String, data: Data)] = [:]
    private(set) var rateLimit: RateLimit?

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20
            config.waitsForConnectivity = false
            config.httpAdditionalHeaders = ["User-Agent": "Cleared/0.3 (+https://github.com/hollandcloud/cleared)"]
            self.session = URLSession(configuration: config)
        }
    }

    func currentRateLimit() -> RateLimit? { rateLimit }

    func clearCache() { cache.removeAll() }

    // MARK: - REST

    struct Response: Sendable {
        let data: Data
        let status: Int
        /// True when GitHub answered 304 and this is the previously cached body.
        let notModified: Bool
    }

    /// Issues a REST request, reusing an ETag when one is known for this path.
    @discardableResult
    func rest(
        _ method: String,
        _ path: String,
        body: (any Encodable & Sendable)? = nil,
        useCache: Bool = false
    ) async throws -> Response {
        guard let token = TokenStore.current() else { throw GitHubError.notAuthenticated }
        guard let url = URL(string: "https://api.github.com/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            throw GitHubError.transport("Bad URL for \(path)")
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

        readRateLimit(from: http)

        if http.statusCode == 304, let cached = cache[cacheKey] {
            return Response(data: cached.data, status: 304, notModified: true)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw GitHubError.http(status: http.statusCode, message: Self.message(from: data))
        }

        if useCache, let etag = http.value(forHTTPHeaderField: "ETag") {
            cache[cacheKey] = (etag, data)
        }

        return Response(data: data, status: http.statusCode, notModified: false)
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

    private func readRateLimit(from http: HTTPURLResponse) {
        guard let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init),
              let limit = http.value(forHTTPHeaderField: "X-RateLimit-Limit").flatMap(Int.init),
              let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init)
        else { return }
        rateLimit = RateLimit(remaining: remaining, limit: limit, resetsAt: Date(timeIntervalSince1970: reset))
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
