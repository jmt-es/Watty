import SwiftUI

struct FreshnessStrip: View {
    @EnvironmentObject var model: BatteryModel
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            indicator
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if model.isSamplingEnergy {
                ProgressView()
                    .controlSize(.mini)
                Text("Sampling apps")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if model.isVisible {
                Text("Live · every \(Int(RefreshCadence.visibleSnapshot)) s")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, PanelMetrics.horizontalPadding)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
        .onAppear { pulse = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Data freshness")
        .accessibilityValue(text)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var indicator: some View {
        switch model.freshness {
        case .waiting:
            Circle()
                .fill(Color.secondary)
                .frame(width: 7, height: 7)
                .opacity(pulse ? 0.25 : 1)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
        case .refreshing:
            ProgressView()
                .controlSize(.mini)
        case .live:
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)
        case .stale:
            Circle()
                .fill(Color.orange)
                .frame(width: 7, height: 7)
        }
    }

    private var text: String {
        switch model.freshness {
        case .waiting:
            return String(localized: "Connecting to power telemetry…")
        case .refreshing:
            return String(localized: "Refreshing…")
        case .live:
            return String(localized: "Updated \(ValueFormat.relative(model.snapshot.lastUpdated, now: model.now))")
        case .stale:
            return String(localized: "Stale · updated \(ValueFormat.relative(model.snapshot.lastUpdated, now: model.now))")
        }
    }
}
