import Foundation

// MARK: - GitHub API Response

private struct GitHubRelease: Codable {
    let tagName: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}

// MARK: - VersionService

class VersionService {
    static let shared = VersionService()
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: configuration)
    }

    /// The installed CLI version, read from disk — deliberately without running a
    /// shell.
    ///
    /// The obvious implementation, `claude --version`, can't just be spawned: a
    /// bundle launched by LaunchServices inherits none of the user's PATH, so it
    /// only worked as `zsh -li -c`, which sources `.zprofile`/`.zshrc` and
    /// executes whatever the user keeps there — hourly, in a child of this
    /// process, to read back one semver. It also cost ~0.7s per check, nearly all
    /// of it shell startup and launching the CLI's own multi-hundred-megabyte
    /// binary. Each source below is a plain file read instead, and each is a
    /// different way an install records its own version.
    ///
    /// The reads are synchronous, which is safe here and needs no `Task.detached`:
    /// a `nonisolated async` method runs on the generic executor rather than the
    /// caller's actor, so this stays off the main thread even though
    /// `UpdateChecker` is `@MainActor`.
    func fetchInstalledVersion() async throws -> String {
        guard let version = Self.installedVersion() else {
            throw VersionError.notFound
        }
        return version
    }

    /// Most authoritative source first: the shim names the version that would run
    /// right now, the update log the one most recently installed, the transcript
    /// the one that last actually ran.
    private static func installedVersion() -> String? {
        versionFromNativeShim()
            ?? versionFromUpdateLog()
            ?? versionFromNewestTranscript()
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// The native installer unpacks each build into
    /// `~/.local/share/claude/versions/<semver>` and repoints `~/.local/bin/claude`
    /// at the active one, so the link target spells out the version. A `readlink`
    /// with no PATH lookup — which is what forced the login shell to begin with.
    private static func versionFromNativeShim() -> String? {
        let shim = home.appendingPathComponent(".local/bin/claude").path
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: shim) else {
            return nil
        }
        return semver(in: (target as NSString).lastPathComponent)
    }

    /// Written by the native updater after every attempt, so only a successful one
    /// describes what is on disk: a failed update still records the build it tried
    /// and never installed in `version_to`.
    private static func versionFromUpdateLog() -> String? {
        let path = home.appendingPathComponent(".claude/.last-update-result.json").path
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["outcome"] as? String == "success",
              let version = json["version_to"] as? String else {
            return nil
        }
        return semver(in: version)
    }

    /// How much of a transcript's tail to scan. Every entry carries a `version`,
    /// so this only has to span the last of them.
    private static let transcriptTailBytes: UInt64 = 64 * 1024

    /// Every transcript entry records the `version` that wrote it, whatever the
    /// install method — the one source that also covers npm and nvm setups, which
    /// have neither a shim nor an update log. It lags by a run: a CLI upgraded but
    /// not yet used still reports the older build, which is why it comes last.
    private static func versionFromNewestTranscript() -> String? {
        guard let path = newestTranscriptPath(),
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return nil
        }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > transcriptTailBytes ? size - transcriptTailBytes : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty else {
            return nil
        }

        // Drop the partial line the offset almost certainly landed inside. That
        // also guarantees what remains starts on a UTF-8 boundary, so decoding
        // can't open with a replacement character mid-token.
        let body: Data
        if offset > 0, let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
            body = data[data.index(after: newline)...]
        } else {
            body = data
        }

        // Last match wins: the tail is chronological, so the final entry belongs
        // to the most recent run.
        return lastVersionField(in: String(decoding: body, as: UTF8.self))
    }

    /// Mirrors `CostService`'s roots so the two agree on where transcripts live.
    private static func newestTranscriptPath() -> String? {
        let roots: [String]
        if let configured = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty {
            roots = [configured]
        } else {
            roots = [
                home.appendingPathComponent(".claude").path,
                home.appendingPathComponent(".config/claude").path
            ]
        }

        var newest: (path: String, modified: Date)?
        for root in roots {
            let projects = "\(root)/projects"
            guard let walker = FileManager.default.enumerator(atPath: projects) else { continue }
            for case let name as String in walker where name.hasSuffix(".jsonl") {
                let path = "\(projects)/\(name)"
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                      let modified = attributes[.modificationDate] as? Date else { continue }
                if modified > (newest?.modified ?? .distantPast) {
                    newest = (path, modified)
                }
            }
        }
        return newest?.path
    }

    // MARK: - Parsing

    /// A bare semver, for a symlink target or a version string carrying a suffix.
    private static let semverPattern = try? NSRegularExpression(pattern: #"(\d+\.\d+\.\d+)"#)

    /// The transcript's own `version` field specifically, so a semver appearing
    /// elsewhere in the entry's JSON can't be mistaken for it.
    private static let versionFieldPattern = try? NSRegularExpression(
        pattern: #""version"\s*:\s*"(\d+\.\d+\.\d+)""#
    )

    private static func semver(in string: String) -> String? {
        capture(semverPattern, in: string)
    }

    private static func lastVersionField(in string: String) -> String? {
        capture(versionFieldPattern, in: string, takingLast: true)
    }

    private static func capture(
        _ regex: NSRegularExpression?,
        in string: String,
        takingLast: Bool = false
    ) -> String? {
        guard let regex else { return nil }
        let matches = regex.matches(in: string, range: NSRange(string.startIndex..., in: string))
        guard let match = takingLast ? matches.last : matches.first,
              let range = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[range])
    }

    // MARK: - Latest release

    func fetchLatestVersion() async throws -> String {
        guard let url = URL(string: "https://api.github.com/repos/anthropics/claude-code/releases/latest") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeCodeStats/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        // Strip leading "v" if present (e.g. "v1.0.30" -> "1.0.30")
        let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        return version
    }
}

enum VersionError: Error {
    case notFound
}
