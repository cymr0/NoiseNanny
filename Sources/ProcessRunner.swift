import Foundation
import os

/// Thread-safe buffer for collecting pipe output from `readabilityHandler` callbacks.
///
/// Uses `OSAllocatedUnfairLock` (available since macOS 14) for minimal-overhead synchronization,
/// replacing the legacy `NSLock` pattern.
private struct PipeBuffer: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: Data())

    func append(_ chunk: Data) {
        storage.withLock { $0.append(chunk) }
    }

    var data: Data {
        storage.withLock { $0 }
    }
}

/// Shared utility for running external processes with async/await and timeouts.
///
/// Consolidates the duplicated process-execution logic previously spread across
/// `SonosCLI` and `CLIInstaller`.
enum ProcessRunner {
    /// Waits for a process to exit without blocking the cooperative thread pool.
    static func waitForExit(_ process: Process) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }

    /// Runs an executable and returns its stdout data. Throws on non-zero exit or timeout.
    static func run(
        _ executablePath: String,
        arguments: [String],
        timeout: TimeInterval = 10
    ) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        // Collect pipe data as it arrives to avoid buffer deadlocks
        let outBuffer = PipeBuffer()
        let errBuffer = PipeBuffer()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { outBuffer.append(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { errBuffer.append(data) }
        }

        // Ensure handlers are cleared on early throw from process.run()
        defer {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
        }

        try process.run()

        // Race process exit against timeout — without blocking the cooperative pool
        let didTimeout = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await waitForExit(process)
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return true
            }
            let first = await group.next()!
            group.cancelAll()
            return first
        }

        // Clear handlers and drain any remaining buffered data
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        let trailingOut = stdout.fileHandleForReading.readDataToEndOfFile()
        if !trailingOut.isEmpty { outBuffer.append(trailingOut) }

        if didTimeout {
            process.terminate()
            throw ProcessRunnerError.timedOut
        }

        if process.terminationStatus != 0 {
            let trailingErr = stderr.fileHandleForReading.readDataToEndOfFile()
            if !trailingErr.isEmpty { errBuffer.append(trailingErr) }
            let errStr = String(data: errBuffer.data, encoding: .utf8) ?? ""
            throw ProcessRunnerError.nonZeroExit(status: process.terminationStatus, stderr: errStr)
        }
        return outBuffer.data
    }

    /// Runs a process and waits for exit with a timeout. Returns `true` if it timed out.
    static func runAndWait(
        _ process: Process,
        timeout: TimeInterval = 30
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await waitForExit(process)
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return true
            }
            let first = await group.next()!
            group.cancelAll()
            return first
        }
    }
}

enum ProcessRunnerError: LocalizedError {
    case timedOut
    case nonZeroExit(status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Command timed out"
        case .nonZeroExit(_, let stderr):
            return "CLI error: \(stderr)"
        }
    }
}
