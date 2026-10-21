import Darwin
import Foundation

protocol ConsoleOutput: AnyObject {
    func write(_ text: String)
    func writeError(_ text: String)
}

final class StandardConsole: ConsoleOutput {
    init() {}

    func write(_ text: String) {
        guard fputs(text, stdout) >= 0, fflush(stdout) == 0 else {
            let reason = String(cString: strerror(errno))
            writeError("\(CLIDefaults.toolName): could not write to standard output: \(reason)\n")
            exit(ExitCode.runtimeFailure)
        }
    }

    func writeError(_ text: String) {
        fputs(text, stderr)
    }
}
