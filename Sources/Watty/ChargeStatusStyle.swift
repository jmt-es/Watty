import SwiftUI
import WattyCore

struct ChargeStatusStyle: Equatable {
    let symbol: String
    let ringSymbol: String?
    let tint: Color
    let textColor: Color
    let subtitleColor: Color

    init(chargeState: ChargeState, level: Int) {
        let isLow = level <= BatteryThreshold.lowLevel
        switch chargeState {
        case .charging:
            self.init(symbol: ChargeSymbol.charging, ringSymbol: ChargeSymbol.charging, tint: .green, textColor: .green)
        case .charged:
            self.init(symbol: "checkmark.circle.fill", ringSymbol: nil, tint: .green, textColor: .green)
        case .pluggedInNotCharging:
            self.init(symbol: "powerplug.fill", ringSymbol: nil, tint: .yellow, textColor: .yellow)
        case .pluggedInDraining:
            self.init(
                symbol: ChargeSymbol.draining,
                ringSymbol: ChargeSymbol.draining,
                tint: .orange,
                textColor: .orange,
                subtitleColor: .orange
            )
        case .onBattery:
            self.init(symbol: "battery.75", ringSymbol: nil, tint: isLow ? .orange : .teal, textColor: isLow ? .orange : .primary)
        case .unknown:
            self.init(symbol: "waveform.path.ecg", ringSymbol: nil, tint: .secondary, textColor: .secondary)
        }
    }

    private init(symbol: String, ringSymbol: String?, tint: Color, textColor: Color, subtitleColor: Color = .secondary) {
        self.symbol = symbol
        self.ringSymbol = ringSymbol
        self.tint = tint
        self.textColor = textColor
        self.subtitleColor = subtitleColor
    }
}
