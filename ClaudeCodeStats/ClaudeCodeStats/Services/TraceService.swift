import Foundation

/// Reads Cloudflare's edge view of this connection from `claude.ai/cdn-cgi/trace`.
///
/// The endpoint answers with `text/plain` — one `key=value` per line, no auth —
/// describing the request Cloudflare just received: which country it placed the
/// client in, which edge datacentre served it, the negotiated protocols. It is
/// the only thing in the app that reports on the path to Claude rather than on
/// usage of it.
class TraceService {
    static let shared = TraceService()

    private let traceURL = "https://claude.ai/cdn-cgi/trace"
    private let session: URLSession

    private init() {
        self.session = URLSession(configuration: HTTP.configuration(timeout: 10))
    }

    func fetch() async throws -> TraceInfo {
        guard let url = URL(string: traceURL) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let body = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        return Self.parse(body)
    }

    /// Splits the response into fields.
    ///
    /// Each line is cut at its *first* `=`, never every `=`: `uag` carries a user
    /// agent string that can contain one, and splitting on all of them would
    /// truncate the value. Unknown keys are ignored, so a field added at the edge
    /// can't break parsing.
    static func parse(_ body: String) -> TraceInfo {
        var fields: [String: String] = [:]
        for line in body.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<separator])
            let value = String(line[line.index(after: separator)...])
            guard !key.isEmpty, !value.isEmpty else { continue }
            fields[key] = value
        }

        return TraceInfo(
            location: fields["loc"],
            colo: fields["colo"],
            ip: fields["ip"],
            httpVersion: fields["http"],
            tls: fields["tls"],
            keyExchange: fields["kex"],
            warp: fields["warp"],
            lastUpdated: Date()
        )
    }
}
