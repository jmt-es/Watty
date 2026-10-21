import Foundation
import WattyCore

enum JSONOutput {
    static func write<Report: Encodable>(_ report: Report, to context: CommandContext) -> Int32 {
        do {
            context.console.write(try ReportEncoder.jsonString(for: report) + "\n")
            return ExitCode.success
        } catch {
            return context.reportFailure("could not encode the JSON report: \(error.localizedDescription)")
        }
    }
}
