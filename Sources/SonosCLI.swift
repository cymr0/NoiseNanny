import Foundation

/// Thread-safe buffer for collecting pipe output from readabilityHandler callbacks.
private final class PipeStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ chunk: Data) {
        lock.lock()
        buffer.append(chunk)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

/// Async wrapper around the sonos CLI binary.
actor SonosCLI {
    private let settings = SettingsStore.shared

    private func binaryPath() throws -> String {
        guard let path = settings.resolvedCLIPath() else {
            throw CLIError.binaryNotFound
        }
        return path
    }

    enum CLIError: LocalizedError {
        case binaryNotFound
        case executionFailed(String)

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return "sonos CLI binary not found. Check Settings or install via Homebrew."
            case .executionFailed(let msg):
                return "CLI error: \(msg)"
            }
        }
    }

    // MARK: - Process helpers

    /// Waits for a process to exit without blocking the cooperative thread pool.
    private func waitForExit(_ process: Process) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }

    // MARK: - Run

    private func run(_ arguments: [String], timeout: TimeInterval = 10) async throws -> Data {
        let path = try binaryPath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        // Collect pipe data as it arrives to avoid buffer deadlocks
        let outStorage = PipeStorage()
        let errStorage = PipeStorage()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { outStorage.append(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { errStorage.append(data) }
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
                await self.waitForExit(process)
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
        if !trailingOut.isEmpty { outStorage.append(trailingOut) }

        if didTimeout {
            process.terminate()
            throw CLIError.executionFailed("Command timed out")
        }

        if process.terminationStatus != 0 {
            let trailingErr = stderr.fileHandleForReading.readDataToEndOfFile()
            if !trailingErr.isEmpty { errStorage.append(trailingErr) }
            let errStr = String(data: errStorage.data, encoding: .utf8) ?? ""
            throw CLIError.executionFailed(errStr)
        }
        return outStorage.data
    }

    // MARK: - Discover

    func discover() async throws -> [Speaker] {
        let data = try await run(["discover", "--format", "json"], timeout: 15)
        let decoder = JSONDecoder()
        // Output is a JSON array: [{...}, ...]
        let entries = try decoder.decode([DiscoverEntry].self, from: data)
        return entries.map { Speaker(ip: $0.ip, name: $0.name, udn: $0.udn) }
    }

    // MARK: - Groups

    func groupStatus() async throws -> GroupStatusResponse {
        let data = try await run(["group", "status", "--all", "--format", "json"], timeout: 15)
        return try JSONDecoder().decode(GroupStatusResponse.self, from: data)
    }

    // MARK: - Status

    func status(speakerName: String) async throws -> StatusResponse {
        // "now" includes nowPlaying metadata when something is playing
        let data = try await run(["now", "--name", speakerName, "--format", "json"])
        return try JSONDecoder().decode(StatusResponse.self, from: data)
    }

    // MARK: - Volume

    func setVolume(speakerName: String, volume: Int) async throws {
        let clamped = max(0, min(100, volume))
        _ = try await run(["volume", "set", "--name", speakerName, "\(clamped)"])
    }

    // MARK: - Playback control

    func pause(speakerName: String) async throws {
        _ = try await run(["pause", "--name", speakerName])
    }

    func stop(speakerName: String) async throws {
        // Try pause first (more graceful), fall back to stop
        do {
            _ = try await run(["pause", "--name", speakerName])
        } catch let pauseError {
            do {
                _ = try await run(["stop", "--name", speakerName])
            } catch let stopError {
                throw CLIError.executionFailed(
                    "Pause failed: \(pauseError.localizedDescription); Stop failed: \(stopError.localizedDescription)"
                )
            }
        }
    }
}
