import SwiftUI
import AppKit

@main
struct ClaudeCodeStatsApp: App {
    @StateObject private var updateChecker = UpdateChecker()
    @StateObject private var viewModel = UsageViewModel()
    @AppStorage("showSessionInMenuBar") private var showSession = false
    @AppStorage("showWeeklyInMenuBar") private var showWeekly = false
    @AppStorage("showFableInMenuBar") private var showFable = false
    @AppStorage(Prefs.showLocationInMenuBar) private var showLocation = false
    @AppStorage("appearancePreference") private var appearance: AppearancePreference = .system

    private var showRings: Bool {
        showSession || showWeekly || showFable
    }

    /// Whether anything in the menu bar needs live data. The flag is fed by the
    /// trace fetch, so it has to keep the 5-minute refresh alive on its own —
    /// otherwise a user showing only the flag would watch it freeze at whatever
    /// the popover last saw.
    private var needsLiveData: Bool {
        showRings || showLocation
    }

    var body: some Scene {
        MenuBarExtra {
            // Scoped to the popover's contents. The label below is deliberately
            // left out so the menu bar icon keeps following the system.
            ContentView()
                .environmentObject(updateChecker)
                .environmentObject(viewModel)
                .appearanceOverride(appearance)
        } label: {
            HStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    if showRings {
                        let sessionPct = viewModel.webUsage?.sessionUsage ?? 0
                        let weeklyPct = viewModel.webUsage?.weeklyUsage ?? 0
                        let fablePct = viewModel.webUsage?.scopedLimits
                            .first(where: { $0.name == "Fable" })?.usage ?? 0
                        Image(nsImage: renderRings(
                            session: showSession ? sessionPct : nil,
                            weekly: showWeekly ? weeklyPct : nil,
                            fable: showFable ? fablePct : nil
                        ))
                    } else {
                        Image(systemName: "chart.bar.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    if updateChecker.hasUpdate {
                        Circle()
                            .fill(.red)
                            .frame(width: 7, height: 7)
                            .offset(x: 4, y: -3)
                    }
                }

                // Drawn as SwiftUI text rather than into the rings bitmap: an
                // emoji flag is a colour glyph, and compositing it into that
                // NSImage would need the image left non-template — which it is,
                // but the text also tracks the menu bar's own font metrics for
                // free. Absent until the first trace arrives, and absent for
                // countries Cloudflare can't name (see TraceInfo.locationFlag).
                if showLocation, let flag = viewModel.trace?.locationFlag {
                    Text(flag)
                }
            }
            .onAppear {
                viewModel.backgroundRefreshEnabled = needsLiveData
            }
            .onChange(of: needsLiveData) { _, newValue in
                viewModel.backgroundRefreshEnabled = newValue
            }
            .onChange(of: showLocation) { _, _ in
                // Turning the flag on with the Trace card off means nothing has
                // ever fetched trace data. Ask for it now instead of leaving the
                // menu bar blank until the next scheduled refresh.
                Task { await viewModel.refreshTrace() }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private func renderRings(session: Double?, weekly: Double?, fable: Double?) -> NSImage {
        let height: CGFloat = 18
        let ringSize: CGFloat = 14
        let ringLineWidth: CGFloat = 2.5
        let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        let textColor = NSColor.labelColor
        let textAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]

        // Build segments: [(label, progress)]
        var segments: [(String, Double)] = []
        if let session { segments.append(("S", session)) }
        if let weekly { segments.append(("W", weekly)) }
        if let fable { segments.append(("F", fable)) }

        // Measure total width
        let separatorWidth: CGFloat = (" | " as NSString).size(withAttributes: textAttrs).width
        var totalWidth: CGFloat = 0
        for (label, _) in segments {
            let labelSize = (label as NSString).size(withAttributes: textAttrs)
            totalWidth += labelSize.width + 2 + ringSize  // label + gap + ring
        }
        // One separator between each pair of segments (count - 1 total)
        totalWidth += separatorWidth * CGFloat(max(0, segments.count - 1))

        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            var x: CGFloat = 0

            for (i, (label, progress)) in segments.enumerated() {
                // Draw separator before second segment
                if i > 0 {
                    let sep = " | " as NSString
                    let sepSize = sep.size(withAttributes: textAttrs)
                    sep.draw(at: NSPoint(x: x, y: (height - sepSize.height) / 2), withAttributes: textAttrs)
                    x += separatorWidth
                }

                // Draw label
                let labelStr = label as NSString
                let labelSize = labelStr.size(withAttributes: textAttrs)
                labelStr.draw(at: NSPoint(x: x, y: (height - labelSize.height) / 2), withAttributes: textAttrs)
                x += labelSize.width + 2

                // Draw ring
                let ringCenter = CGPoint(x: x + ringSize / 2, y: height / 2)
                let radius = (ringSize - ringLineWidth) / 2
                self.drawRing(in: ctx, center: ringCenter, radius: radius,
                              lineWidth: ringLineWidth, progress: progress)
                x += ringSize
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private func drawRing(in ctx: CGContext, center: CGPoint, radius: CGFloat, lineWidth: CGFloat, progress: Double) {
        let startAngle = CGFloat.pi / 2

        // Track
        ctx.setStrokeColor(NSColor.gray.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.butt)
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ctx.strokePath()

        // Progress arc
        let clamped = max(0.0, min(progress, 100.0))
        let endAngle = startAngle - CGFloat(clamped / 100.0) * 2 * .pi
        ctx.setStrokeColor(ringColor(for: clamped).cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        ctx.strokePath()
    }

    private func ringColor(for progress: Double) -> NSColor {
        if progress < 50 {
            return NSColor(red: 74/255, green: 222/255, blue: 128/255, alpha: 1)
        } else if progress < 75 {
            return NSColor(red: 250/255, green: 204/255, blue: 21/255, alpha: 1)
        } else {
            return NSColor(red: 248/255, green: 113/255, blue: 113/255, alpha: 1)
        }
    }
}
