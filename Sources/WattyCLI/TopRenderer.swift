import Foundation
import WattyCore

enum TopRenderer {
    private static let cpuWidth = 7
    private static let memoryWidth = 9
    private static let columnGap = "  "
    private static let minimumNameWidth = 12
    private static let truncationMark = "…"

    static func lines(for report: TopReport, columns: Int?, style: TextStyle) -> [String] {
        let title = style.bold("Top apps by CPU")
            + style.dim("\(TextFormat.separator)averaged over \(TextFormat.seconds(report.intervalSeconds))")
        guard !report.consumers.isEmpty else {
            let threshold = String(format: "%g", ProcessEnergySampler.minimumCPUPercent)
            return [title, "No app is using more than \(threshold)% CPU."]
        }

        let fixedWidth = cpuWidth + memoryWidth + 2 * columnGap.count
        let nameWidth = columns.map { max(minimumNameWidth, $0 - fixedWidth) }
        let header = style.bold(
            padded("CPU", width: cpuWidth) + columnGap + padded("MEMORY", width: memoryWidth) + columnGap + "APP"
        )
        return [title, header] + report.consumers.map { row($0, nameWidth: nameWidth, style: style) }
    }

    private static func row(_ consumer: TopReport.Consumer, nameWidth: Int?, style: TextStyle) -> String {
        let cpu = padded(TextFormat.percent(consumer.cpuPercent), width: cpuWidth)
        let memoryText = padded(TextFormat.bytes(consumer.memoryBytes), width: memoryWidth)
        let memory = consumer.memoryBytes == nil ? style.dim(memoryText) : memoryText
        let name = nameWidth.map { truncated(consumer.name, to: $0) } ?? consumer.name
        return cpu + columnGap + memory + columnGap + name
    }

    private static func padded(_ text: String, width: Int) -> String {
        String(repeating: " ", count: max(0, width - text.count)) + text
    }

    private static func truncated(_ text: String, to width: Int) -> String {
        guard text.count > width else { return text }
        return String(text.prefix(width - truncationMark.count)) + truncationMark
    }
}
