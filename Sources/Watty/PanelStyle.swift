import SwiftUI

enum PanelMetrics {
    static let width: CGFloat = 344
    static let horizontalPadding: CGFloat = 14
    static let sectionVerticalPadding: CGFloat = 10
}

enum BatteryThreshold {
    static let lowLevel = 20
}

extension View {
    func panelSection() -> some View {
        padding(.horizontal, PanelMetrics.horizontalPadding)
            .padding(.vertical, PanelMetrics.sectionVerticalPadding)
    }
}

struct SectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }
}
