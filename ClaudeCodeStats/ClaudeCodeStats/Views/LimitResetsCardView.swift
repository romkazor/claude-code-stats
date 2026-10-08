import SwiftUI

/// One-off usage-limit resets on offer, as claude.ai lists them under Usage.
/// Read-only: claiming a reset is left to Claude Code and claude.ai.
struct LimitResetsCardView: View {
    let resets: LimitResets

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Limit resets")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 4) {
                fullResetRows
                labelled("5-hour reset") {
                    value(resets.sessionResetAvailable ? "Available" : sessionResetPending,
                          available: resets.sessionResetAvailable)
                }
            }
        }
        .padding(12)
        .background(Theme.cardBackground)
        .cornerRadius(8)
    }

    // Split out of `body`: CI builds on Xcode 16.2, whose type-checker gives up on
    // long single expressions that compile fine on newer toolchains.
    @ViewBuilder
    private var fullResetRows: some View {
        if resets.grants.isEmpty {
            labelled("Full reset") { value("None", available: false) }
        } else {
            ForEach(resets.grants) { grant in
                labelled("Full reset") {
                    value(grantSummary(grant), available: grant.resetsLeft > 0)
                }
                .help(grant.label)
            }
        }
    }

    private var sessionResetPending: String {
        guard let next = resets.sessionResetNextAt else { return "None" }
        return "from \(Self.dateFormatter.string(from: next))"
    }

    private func grantSummary(_ grant: ResetGrant) -> String {
        let count = grant.resetsTotal > 1
            ? "\(grant.resetsLeft) of \(grant.resetsTotal) left"
            : "\(grant.resetsLeft) left"
        guard let endsAt = grant.endsAt else { return count }
        return "\(count) · until \(Self.dateFormatter.string(from: endsAt))"
    }

    private func value(_ text: String, available: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(available ? Theme.statusOK : Theme.textSecondary)
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
        LimitResetsCardView(resets: LimitResets(
            grants: [ResetGrant(
                id: "opus55-launch-promax-20260921",
                label: "Claude Opus 5.5 launch: one usage-limit reset for Pro and Max",
                resetsLeft: 1,
                resetsTotal: 1,
                endsAt: Date().addingTimeInterval(14 * 86_400)
            )],
            sessionResetAvailable: false,
            sessionResetNextAt: nil
        ))

        // Nothing on offer except the 5-hour reset.
        LimitResetsCardView(resets: LimitResets(
            grants: [],
            sessionResetAvailable: true,
            sessionResetNextAt: nil
        ))
    }
    .padding()
    .frame(width: 280)
    .background(Theme.background)
}
