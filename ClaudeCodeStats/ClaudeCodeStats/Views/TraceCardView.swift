import SwiftUI

/// Cloudflare's view of the connection to Claude: which country and edge
/// datacentre served this machine, and what was negotiated to get there.
struct TraceCardView: View {
    let trace: TraceInfo

    /// Whether the full IP is on screen. Deliberately view state rather than a
    /// stored preference: closing the popover discards it, so an address revealed
    /// once isn't still exposed the next time the popover opens.
    @State private var isIPRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trace")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 4) {
                locationRow
                ipRow
                row("Edge", trace.colo)
                row("HTTP", trace.httpVersion)
                row("TLS", trace.tls)
                row("Key exch.", trace.keyExchange)
                row("WARP", trace.warp)
            }
        }
        .padding(12)
        .background(Theme.cardBackground)
        .cornerRadius(8)
    }

    // Split out of `body`: CI builds on Xcode 16.2, whose type-checker gives up on
    // long single expressions that compile fine on newer toolchains.
    @ViewBuilder
    private var locationRow: some View {
        if let location = trace.location {
            labelled("Location") {
                HStack(spacing: 4) {
                    if let flag = trace.locationFlag {
                        Text(flag)
                            .font(.system(size: 11))
                    }
                    Text(location)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private var ipRow: some View {
        if let masked = trace.maskedIP {
            labelled("IP") {
                Text(isIPRevealed ? (trace.ip ?? masked) : masked)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .contentShape(Rectangle())
            .onTapGesture { isIPRevealed.toggle() }
            .help(isIPRevealed ? "Hide the address" : "Show the full address")
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value {
            labelled(label) {
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
            }
        }
    }

    private func labelled<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)

            Spacer(minLength: 0)

            content()
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        TraceCardView(trace: TraceInfo(
            location: "DE",
            colo: "FRA",
            ip: "203.0.113.42",
            httpVersion: "http/2",
            tls: "TLSv1.3",
            keyExchange: "X25519",
            warp: "off",
            lastUpdated: Date()
        ))

        // Unknown country, IPv6, and missing fields.
        TraceCardView(trace: TraceInfo(
            location: "XX",
            colo: nil,
            ip: "2a00:1370:8188:1d1c:aaaa:bbbb:cccc:dddd",
            httpVersion: "http/3",
            tls: nil,
            keyExchange: nil,
            warp: "on",
            lastUpdated: Date()
        ))
    }
    .padding()
    .frame(width: 280)
    .background(Theme.background)
}
