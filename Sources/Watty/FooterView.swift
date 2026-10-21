import SwiftUI
import WattyCore

struct FooterView: View {
    @EnvironmentObject var model: BatteryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !warnings.isEmpty {
                Label(warnings.joined(separator: " · "), systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            HStack {
                Text(model.versionText)
                Spacer()
                if let trigger = model.lastTrigger {
                    Text(trigger.localizedLastRefresh(milliseconds: Int(model.snapshot.readDuration * 1000)))
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, PanelMetrics.horizontalPadding)
        .padding(.bottom, 8)
    }

    private var warnings: [String] {
        model.snapshot.warnings.map(SnapshotWarning.localizedMessage(for:)) + [model.historyWarning].compactMap { $0 }
    }
}
