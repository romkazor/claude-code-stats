import SwiftUI

/// Pay-as-you-go usage past the plan's limits, against its spending cap.
struct ExtraUsageCardView: View {
    let extra: ExtraUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Extra usage")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textPrimary)

            HStack(spacing: 12) {
                ProgressBarView(progress: extra.percent)

                Text("\(Int(extra.percent))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .frame(width: 40, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Text(amounts)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)

                Spacer(minLength: 0)

                Text(status)
                    .font(.system(size: 11))
                    .foregroundColor(extra.isEnabled ? Theme.statusOK : Theme.textSecondary)
            }
        }
        .padding(12)
        .background(Theme.cardBackground)
        .cornerRadius(8)
    }

    private var amounts: String {
        let used = money(extra.used)
        guard let limit = extra.limit else { return "\(used) spent" }
        return "\(used) of \(money(limit))"
    }

    // The server's reason is a snake_case code, e.g. `out_of_credits`.
    private var status: String {
        if extra.isEnabled { return "On" }
        guard let reason = extra.disabledReason else { return "Off" }
        return "Off · \(reason.replacingOccurrences(of: "_", with: " "))"
    }

    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: extra.currency))
    }
}

#Preview {
    VStack(spacing: 12) {
        ExtraUsageCardView(extra: ExtraUsage(
            used: 0, limit: 10, currency: "EUR", percent: 0,
            isEnabled: false, disabledReason: "out_of_credits"
        ))
        ExtraUsageCardView(extra: ExtraUsage(
            used: 27.14, limit: 50, currency: "USD", percent: 54,
            isEnabled: true, disabledReason: nil
        ))
    }
    .padding()
    .frame(width: 280)
    .background(Theme.background)
}
