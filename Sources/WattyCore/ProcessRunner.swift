import Foundation
import os

protocol CommandRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> ProcessRunner.Result
}

struct ProcessRunner: CommandRunning {
    struct Result {
        let stdout: String
        let stderr: String
        let terminationStatus: Int32
        let didTimeOut: Bool
        let duration: TimeInterval

        var succeeded: Bool {
            terminationStatus == 0 && !didTimeOut
        }
    }

    private static let killGracePeriod: TimeInterval = 2

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> Result {
        let startedAt = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let drain = DispatchGroup()
        var stdoutData = Data()
        var stderrData = Data()
        drain.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            drain.leave()
        }
        drain.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            drain.leave()
        }

        do {
            try process.run()
        } catch {
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            drain.wait()
            return Result(
                stdout: "",
                stderr: error.localizedDescription,
                terminationStatus: -1,
                didTimeOut: false,
                duration: Date().timeIntervalSince(startedAt)
            )
        }

        let lock = NSLock()
        var didTimeOut = false
        let timeoutWork = DispatchWorkItem {
            lock.lock()
            defer { lock.unlock() }
            guard process.isRunning else { return }
            didTimeOut = true
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.killGracePeriod) {
                if process.isRunning {
                    kill(pid, SIGKILL)
                }
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

        process.waitUntilExit()
        timeoutWork.cancel()
        drain.wait()

        lock.lock()
        let timedOut = didTimeOut
        lock.unlock()

        return Result(
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            terminationStatus: timedOut ? 124 : process.terminationStatus,
            didTimeOut: timedOut,
            duration: Date().timeIntervalSince(startedAt)
        )
    }
}

extension Logger {
    func logCommandFailure(_ command: String, _ result: ProcessRunner.Result) {
        let diagnostics = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        error("\(command, privacy: .public) failed status=\(result.terminationStatus) timedOut=\(result.didTimeOut) stderr=\(diagnostics, privacy: .public)")
    }
}
