import SwiftUI
import WattyCore

struct EnergyModeView: View {
    @EnvironmentObject var model: BatteryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                SectionTitle("Energy Mode")
                Spacer()
                Text(currentModeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Picker("Mode", selection: $model.selectedPowerMode) {
                ForEach(model.availablePowerModes) { mode in
                    Text(mode.localizedTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.applyingPowerMode != nil || model.snapshot.isEmpty)

            statusLine
        }
        .panelSection()
    }

    private var currentModeText: String {
        guard let mode = model.snapshot.powerMode else { return String(localized: "Mode unknown") }
        if mode == .lowPower, model.snapshot.lowPowerModeActive == false {
            return String(localized: "Low Power set · not active yet")
        }
        return String(localized: "Current: \(mode.localizedLongTitle)")
    }

    @ViewBuilder
    private var statusLine: some View {
        if let applying = model.applyingPowerMode {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text(String(localized: "Applying \(applying.localizedLongTitle)… enter the admin password"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else if let status = model.actionStatus {
            Label(status.localizedMessage, systemImage: status.success ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(status.success ? Color.green : Color.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            Text("Changing the mode asks for the administrator password")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }
}
