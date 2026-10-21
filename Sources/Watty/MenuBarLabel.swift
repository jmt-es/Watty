import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var model: BatteryModel
    let display: MenuBarDisplay

    var body: some View {
        let content = MenuBarContent(
            snapshot: model.snapshot,
            cpuPercent: model.stats?.cpu?.totalPercent,
            display: display
        )

        HStack(spacing: 3) {
            Image(systemName: content.symbolName)
                .symbolRenderingMode(.hierarchical)
            if let text = content.text {
                Text(text)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityValue(content.accessibilityValue ?? "")
    }
}
