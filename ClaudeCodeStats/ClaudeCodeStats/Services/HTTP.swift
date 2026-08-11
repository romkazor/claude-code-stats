import Foundation

/// Shared outbound HTTP setup.
///
/// Exists so the User-Agent has exactly one definition. It is spelled as a
/// current desktop Chrome rather than as this app, which means it will read as
/// stale once that Chrome version ages out — a one-line edit here, and nowhere
/// else.
enum HTTP {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36"

    /// A session configuration carrying the shared User-Agent.
    ///
    /// `httpAdditionalHeaders` is the whole point: it applies to every request a
    /// session makes, so no call site has to remember the header. A per-request
    /// `setValue(_:forHTTPHeaderField: "User-Agent")` would silently win over
    /// this, so call sites must not set one.
    static func configuration(timeout: TimeInterval) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        return configuration
    }
}
