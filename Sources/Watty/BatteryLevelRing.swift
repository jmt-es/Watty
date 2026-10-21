import SwiftUI

struct BatteryLevelRing: View {
    static let diameter: CGFloat = 40
    static let lineWidth: CGFloat = 5
    static let trackOpacity = 0.22
    static let chargingGlyphSize: CGFloat = 14

    let level: Int
    let tint: Color
    let isCharging: Bool

    static func fraction(forLevel level: Int) -> Double {
        Double(min(max(level, 0), 100)) / 100
    }

    var body: some View {
        let fraction = Self.fraction(forLevel: level)

        ZStack {
            Circle()
                .inset(by: Self.lineWidth / 2)
                .stroke(tint.opacity(Self.trackOpacity), lineWidth: Self.lineWidth)

            if fraction > 0 {
                Circle()
                    .inset(by: Self.lineWidth / 2)
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            if isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: Self.chargingGlyphSize, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery level")
        .accessibilityValue(ValueFormat.percent(level))
    }
}
