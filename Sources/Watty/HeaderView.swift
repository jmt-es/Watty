import SwiftUI
import WattyCore

struct HeaderView: View {
    @EnvironmentObject var model: BatteryModel

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Watty")
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            RefreshButton()
            HeaderMenu()
        }
        .padding(.horizontal, PanelMetrics.horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var subtitle: String {
        model.hasBattery ? model.snapshot.chargeState.localizedTitle : String(localized: "Desktop Mac · no battery")
    }

    private var statusSymbol: String {
        guard model.hasBattery else { return "desktopcomputer" }
        switch model.snapshot.chargeState {
        case .charging: return "bolt.fill"
        case .charged: return "checkmark.circle.fill"
        case .pluggedInNotCharging: return "powerplug.fill"
        case .onBattery: return "battery.75"
        case .unknown: return "waveform.path.ecg"
        }
    }

    private var statusColor: Color {
        guard model.hasBattery else { return .teal }
        switch model.snapshot.chargeState {
        case .charging, .charged: return .green
        case .pluggedInNotCharging: return .yellow
        case .onBattery: return model.snapshot.level <= BatteryThreshold.lowLevel ? .orange : .teal
        case .unknown: return .secondary
        }
    }
}

private struct RefreshButton: View {
    @EnvironmentObject var model: BatteryModel

    var body: some View {
        Button(action: model.refreshNow) {
            ZStack {
                Image(systemName: "arrow.clockwise")
                    .opacity(model.showsManualSpinner ? 0 : 1)
                if model.showsManualSpinner {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .disabled(model.showsManualSpinner)
        .help("Refresh now")
        .accessibilityLabel("Refresh now")
    }
}

private struct HeaderMenu: View {
    @EnvironmentObject var model: BatteryModel

    var body: some View {
        Menu {
            Button("Settings…") {
                SettingsOpener.shared.open()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button {
                model.openBatterySettings()
            } label: {
                Text(systemSettingsTitle)
            }

            Divider()

            Button("About Watty") {
                AboutPanel.show()
            }

            Divider()

            Button("Quit Watty") {
                model.quit()
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 18, height: 18)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More options")
        .accessibilityLabel("More options")
    }

    private var systemSettingsTitle: LocalizedStringKey {
        model.hasBattery ? "Open Battery Settings…" : "Open Energy Settings…"
    }
}
