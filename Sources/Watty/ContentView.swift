import SwiftUI
import WattyCore

struct ContentView: View {
    enum Surface {
        case menuBar
        case panel
    }

    static let width = PanelMetrics.width

    @EnvironmentObject var model: BatteryModel
    var surface: Surface = .menuBar

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            FreshnessStrip()
            Divider()
            if model.hasBattery {
                BatteryOverviewView()
                Divider()
            }
            ActivityView()
            Divider()
            if showsPowerFlow {
                PowerFlowView()
                Divider()
            }
            EnergyConsumersView()
            Divider()
            if model.hasBattery {
                HealthView()
                Divider()
            }
            EnergyModeView()
            FooterView()
        }
        .frame(width: Self.width)
        .background(Color(nsColor: .windowBackgroundColor))
        .background {
            if surface == .menuBar {
                SettingsActionRegistrar()
            }
        }
        .onAppear {
            if surface == .menuBar { model.surfaceDidAppear() }
        }
        .onDisappear {
            if surface == .menuBar { model.surfaceDidDisappear() }
        }
    }

    private var showsPowerFlow: Bool {
        model.hasBattery || model.snapshot.systemPowerWatts != nil || model.snapshot.systemLoadWatts != nil
    }
}
