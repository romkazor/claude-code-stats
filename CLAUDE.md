# CLAUDE.md

## Project Overview

ClaudeCodeStats is a native macOS menu bar app (SwiftUI) that shows Claude Code usage limits, Claude service health status, and CLI version update notifications.

## Build

```bash
cd ClaudeCodeStats
xcodebuild -scheme ClaudeCodeStats -configuration Release build
```

The built `.app` is in `~/Library/Developer/Xcode/DerivedData/ClaudeCodeStats-*/Build/Products/Release/`.

To install locally:

```bash
# Kill running instance, copy to /Applications, relaunch
pkill -x ClaudeCodeStats; sleep 0.5
rm -rf /Applications/ClaudeCodeStats.app
cp -R ~/Library/Developer/Xcode/DerivedData/ClaudeCodeStats-*/Build/Products/Release/ClaudeCodeStats.app /Applications/
open /Applications/ClaudeCodeStats.app
```

### Sign local builds with a stable certificate

The project signs ad-hoc (`CODE_SIGN_IDENTITY = "-"`), which is right for CI but painful for local development: an ad-hoc signature's identity **is** the binary's hash, so every rebuild looks like a different app to the system. The visible symptom is the keychain — the app reads the CLI's `Claude Code-credentials` item, and "Always Allow" is bound to the app's identity, so each rebuild silently revokes it and the permission dialog returns.

Create a self-signed code-signing certificate once, mark it trusted for code signing, and build with it. Both halves matter, and the second one is easy to skip: `codesign` happily signs with an untrusted certificate, so the build succeeds and the app runs — but the keychain still re-prompts. Its ACL check validates the signing chain, and an untrusted chain never matches the stored entry, however many times you click "Always Allow".

```bash
# One-off: generate, then import into the login keychain
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
  -subj "/CN=ClaudeCodeStats Local Signing" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"
# -legacy matters: OpenSSL 3's default PKCS#12 MAC fails Security.framework's check
openssl pkcs12 -export -out cert.p12 -inkey key.pem -in cert.pem \
  -passout pass:temp -name "ClaudeCodeStats Local Signing" -legacy
security import cert.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign -P temp
# Trust it for code signing only — this is what makes the keychain ACL stick
sudo security add-trusted-cert -d -r trustRoot -p codeSign \
  -k /Library/Keychains/System.keychain cert.pem
```

Then pass it on every local build — do **not** commit it into `project.pbxproj`, or CI and everyone without this certificate breaks:

```bash
xcodebuild -scheme ClaudeCodeStats -configuration Release \
  CODE_SIGN_IDENTITY="ClaudeCodeStats Local Signing" build
```

Two checks confirm it worked. `security verify-cert -c cert.pem -p codeSign` must say `certificate verification successful` — before the trust step it reports `CSSMERR_TP_NOT_TRUSTED`, which is the state that leaves the keychain re-prompting. And `codesign -d -r- /Applications/ClaudeCodeStats.app` should print a designated requirement naming the certificate rather than a binary hash:

```
identifier "com.claudecodestats.app" and certificate leaf = H"…"
```

That is the whole point — the requirement now survives rebuilds, because it pins the certificate instead of the binary.

Note that `add-trusted-cert` leaves a second copy of the certificate in the System keychain, so `security find-identity -v -p codesigning` lists the same identity twice. Both entries share one hash, but if `codesign -s "ClaudeCodeStats Local Signing"` ever complains about ambiguity, pass the SHA-1 instead.

Switching from ad-hoc to the certificate invalidates the app's own cached keychain item, created under the old identity. Delete it once so the app recreates it, otherwise the first launch costs an extra prompt:

```bash
security delete-generic-password -s "ClaudeCodeStats-credentials"
```

### Verifying changes

There are no tests or linters configured, so verifying a change means running the app and looking at it. Three non-obvious traps when doing that from a shell:

- **Launch with `open`, never `&`.** A `.app` started as `"$BINARY" &` from a Bash tool dies when that shell returns, often mid-work — `open /Applications/ClaudeCodeStats.app` hands it to LaunchServices so it survives. To time a scan or wait on a side effect, poll the artifact (`until [ -f "$cost_cache" ]; do sleep 2; done`), don't hold the process open.
- **Instrument to a file, not stderr.** A menu bar app has no attached terminal, and one you'll `pkill` loses buffered stdout/stderr — write debug lines to a file (`/tmp/…`) and `cat` it after.
- **AppleScript can't open the MenuBarExtra popover** (`click menu bar item …` does nothing). To inspect a view in a specific state or appearance without the running app, compile the real views into a standalone `ImageRenderer` harness and render at a chosen `\.colorScheme` + sample data (`swiftc main.swift Theme.swift Models.swift Views/*.swift` — top-level code needs the file named `main.swift`). It renders everything except `ScrollView` content, which comes back blank.

`CostService` spend is validated against `npx ccusage` — but ccusage and a fresh scan **must be measured at the same instant**. A live corpus grows every few seconds while Claude Code runs, so a scan compared against a ccusage snapshot from minutes earlier shows a false delta (this produced a confidently-wrong "0.7% residual" that was pure skew; measured together, they agree to the cent on unused models).

## Architecture

- **App entry point**: `ClaudeCodeStatsApp.swift` — `MenuBarExtra` with chart icon, red dot badge overlay for updates
- **Main view**: `ContentView.swift` — contains the `UsageViewModel` (handles usage data + status polling) and all view components
- **Services** (singletons, async/await):
  - `OAuthUsageService` — fetches usage data from the Anthropic `GET /api/oauth/usage` endpoint using OAuth credentials (reads `~/.claude/.credentials.json` first, falls back to macOS Keychain `Claude Code-credentials`), decoding session, weekly all-models, and per-model scoped weekly limits (e.g. Fable) from the JSON `limits` array. **Never call `hasCredentials` from a SwiftUI `body`**: it walks the full token cascade, and on the common macOS setup (no credentials file — the CLI keeps the token in the keychain) that cascade reaches the keychain, which can raise a system permission prompt once the cached token has rotated out. A body re-evaluates on every state change, so one screen turned into several prompts. `UsageViewModel.hasCredentials` samples it once per refresh; views read that
  - `CostService` — computes API-equivalent spend by scanning the Claude Code transcripts in `~/.claude/projects/**/*.jsonl`. An `actor`, not a `@MainActor` singleton: a cold scan parses the entire corpus (gigabytes, seconds of CPU) and has to stay off the main thread. Caches per-day rollups in Application Support and resumes each transcript from a byte offset, so a warm refresh re-reads only what was appended — usually nothing, and it then skips the cache write too. Any change to its price table, cost formula, or parsing **must** bump `cacheVersion` — costs are priced once at scan time and offsets advance regardless, so otherwise the change is silently ignored
  - `StatusService` — fetches health status from status.claude.com
  - `TraceService` — reads Cloudflare's edge view of the connection from `claude.ai/cdn-cgi/trace`, a plain-text `key=value` body. Lines are cut at their **first** `=` because `uag` carries a user agent that can contain one; unknown keys are ignored. Gated on `TraceSettings.isEnabled` in `UsageViewModel.refreshTrace()`, not in the view — a disabled card must cost no request, not merely stay hidden
  - `HTTP` — the single definition of the app's User-Agent (a desktop Chrome string) plus a `URLSessionConfiguration` factory. Every service builds its session from it. Call sites must **not** set a per-request `User-Agent` header: that overrides `httpAdditionalHeaders` and silently reintroduces a second UA
  - `VersionService` — resolves the installed CLI version from disk and the latest release from the GitHub API; includes `UpdateChecker` ObservableObject for state management. It **never spawns a shell**: a GUI bundle inherits no PATH, so `claude --version` only ran as `zsh -li -c`, which sources the user's `.zprofile`/`.zshrc` — executing whatever lives there, hourly, to read back one semver — and cost ~0.7s a check. Three file sources are tried in order of authority: the native installer's `~/.local/bin/claude` symlink (its target is `…/versions/<semver>`, so the link names the version that would run right now), then `~/.claude/.last-update-result.json` (`version_to`, and only when `outcome` is `success` — a failed update still records the build it never installed), then the `version` field in the tail of the newest `~/.claude/projects/**/*.jsonl` transcript. The transcript comes last because it lags by a run, but it is the only source that also covers npm and nvm installs, which have neither a shim nor an update log

## Patterns

- Services are singletons with `static let shared` and private `init()`
- Non-critical features (status, version check) fail silently
- `@MainActor` on ObservableObjects, `@Published` for reactive state
- `@AppStorage` for persisted user preferences (e.g. dismissed update version). Keys the view model also reads live in `Prefs` (`Models.swift`) — `@AppStorage` is a `DynamicProperty` for `View` and never publishes from an `ObservableObject`, so `UsageViewModel` reads `UserDefaults` through `Prefs` instead. Read a default-on toggle with `Prefs.bool(_:default:)`, never `UserDefaults.bool(forKey:)`: the latter reports `false` for an unset key and would turn the toggle off until flipped twice
- Card toggles gate the **work**, not just the view: with a card off, `UsageViewModel` skips the transcript scan / the RTK database read / the trace request. The trace fetch is shared with the menu bar flag, so it is gated on `Prefs.needsTrace` (either consumer) rather than on the card alone
- Auto-refresh timers: 5 min for usage, 1 hour for version checks
- The app sandbox is disabled (`com.apple.security.app-sandbox = false`)
- Colors are defined in `Theme.swift` (`Theme.background`, `Theme.cardBackground`, `Theme.textSecondary`, etc.) — always use `Theme.*` constants, never inline color literals or local computed properties
- Large SwiftUI `body` properties must be split into extracted computed properties (e.g. `menuBarDisplaySection`) — CI uses Xcode 16.2 whose Swift type-checker fails on complex single-body expressions that may compile locally on newer Xcode

## Xcode Project

When adding new `.swift` files, they must be added to `project.pbxproj` in four places:
1. `PBXBuildFile` section (build file reference, e.g. `A13`)
2. `PBXFileReference` section (file reference, e.g. `B15`)
3. The appropriate `PBXGroup` (Services or Views)
4. `PBXSourcesBuildPhase` files list

## Branch Naming

- `fix/<description>` — bug fixes (e.g. `fix/version-check-cancellation`)
- `<feature-name>` — new features and enhancements (e.g. `menubar`)

## Commit Style

Imperative mood, concise first line describing the change. Examples:
- `Add Claude Code version update detection`
- `Fix status indicator: nested buttons, missing timeout, dead code`
- `Clean up status indicator: consolidate logic, add concurrency guard`

## CI/CD

GitHub Actions workflow (`.github/workflows/release.yml`) triggers on release creation:
- Builds universal binary (arm64 + x86_64)
- Uploads ZIP to the GitHub release
- Updates the Homebrew tap (`dmelo/homebrew-tap`) with new version and SHA256
