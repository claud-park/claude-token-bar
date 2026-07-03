import Foundation

// MARK: - Binary resolution

enum CCUsageResolution: Sendable {
    case direct(path: String)
    case npx(npxPath: String)
}

enum CCUsageResolver {
    /// Minimum ccusage major version whose pricing table knows current Claude
    /// models. Older globals (e.g. a stale v17 in /usr/local/bin) report correct
    /// tokens but $0 costs, so they must be rejected in favor of the npx pin.
    static let minimumMajorVersion = 20

    /// Resolves the ccusage command per spec: fixed candidate paths, then `which`,
    /// then a pinned-major npx fallback. Direct binaries are accepted only if
    /// `--version` reports major >= minimumMajorVersion. Performs blocking
    /// file/process work — callers must invoke this off the main thread.
    static func resolve() -> CCUsageResolution? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            "/opt/homebrew/bin/ccusage",
            "/usr/local/bin/ccusage",
            home.appendingPathComponent(".local/bin/ccusage").path
        ]
        for candidate in candidates
        where FileManager.default.isExecutableFile(atPath: candidate) && hasSupportedVersion(candidate) {
            return .direct(path: candidate)
        }
        if let which = runWhich("ccusage"), hasSupportedVersion(which) {
            return .direct(path: which)
        }
        if let npx = findNpx() {
            return .npx(npxPath: npx)
        }
        return nil
    }

    private static func hasSupportedVersion(_ path: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return false
        }
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return false }
        return isSupportedVersion(output)
    }

    /// Parses the leading semver major out of `--version` output (which may
    /// contain a prefix like "ccusage 20.0.14") and checks the minimum.
    static func isSupportedVersion(_ versionOutput: String) -> Bool {
        let pattern = /(\d+)\.\d+\.\d+/
        guard let match = versionOutput.firstMatch(of: pattern),
              let major = Int(match.1) else { return false }
        return major >= minimumMajorVersion
    }

    private static func findNpx() -> String? {
        if let which = runWhich("npx") {
            return which
        }
        for dir in ["/opt/homebrew/bin", "/usr/local/bin"] {
            let candidate = dir + "/npx"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Runs `which <name>` via /usr/bin/env with PATH augmented to include
    /// /opt/homebrew/bin, per spec.
    private static func runWhich(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]

        var environment = ProcessInfo.processInfo.environment
        let extraPath = "/opt/homebrew/bin:/usr/local/bin"
        if let existing = environment["PATH"], !existing.isEmpty {
            environment["PATH"] = extraPath + ":" + existing
        } else {
            environment["PATH"] = extraPath + ":/usr/bin:/bin"
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty,
              FileManager.default.isExecutableFile(atPath: output)
        else { return nil }
        return output
    }
}

// MARK: - Process execution with timeout

struct ProcessRunResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let timedOut: Bool
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        lock.lock()
        storage.append(chunk)
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

enum ProcessRunner {
    /// Runs a process with a hard timeout, capturing stdout/stderr separately.
    /// Blocking — must be called from a background context.
    static func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL,
        timeout: TimeInterval
    ) -> ProcessRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return ProcessRunResult(stdout: "", stderr: "\(error)", exitCode: -1, timedOut: false)
        }

        let outBox = DataBox()
        let errBox = DataBox()
        let readGroup = DispatchGroup()

        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            outBox.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            readGroup.leave()
        }
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            readGroup.leave()
        }

        let timedOutBox = DataBox() // reused only as a thread-safe boolean-ish flag holder
        var didTimeOut = false
        let timeoutLock = NSLock()
        let killQueue = DispatchQueue(label: "com.claudetokenbar.ccusage-timeout")
        let killWorkItem = DispatchWorkItem {
            if process.isRunning {
                timeoutLock.lock()
                didTimeOut = true
                timeoutLock.unlock()
                process.terminate()
            }
        }
        killQueue.asyncAfter(deadline: .now() + timeout, execute: killWorkItem)

        process.waitUntilExit()
        killWorkItem.cancel()
        readGroup.wait()
        _ = timedOutBox // silence unused-var concerns for the placeholder box

        timeoutLock.lock()
        let wasTimedOut = didTimeOut
        timeoutLock.unlock()

        return ProcessRunResult(
            stdout: String(data: outBox.value, encoding: .utf8) ?? "",
            stderr: String(data: errBox.value, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus,
            timedOut: wasTimedOut
        )
    }
}

// MARK: - Defensive JSON extraction

enum JSONExtractor {
    /// Scans `text` for the first `{` whose parse succeeds AND whose top-level
    /// object contains `expectedKey`. Returns the raw JSON slice as `Data` for
    /// typed decoding, or nil if no such object is found.
    static func extractJSONObject(from text: String, expectedKey: String) -> Data? {
        var searchStart = text.startIndex
        while let braceIndex = text[searchStart...].firstIndex(of: "{") {
            let candidate = text[braceIndex...]
            if let data = candidate.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               object[expectedKey] != nil {
                return data
            }
            searchStart = text.index(after: braceIndex)
        }
        return nil
    }
}

// MARK: - Provider

actor CCUsageProvider {
    enum FetchError: Error, Sendable {
        case ccusageUnavailable
        case timeout
        case invalidOutput
        case processFailed(String)
    }

    private var cachedResolution: CCUsageResolution??

    func fetchBlocks() async throws -> BlocksResponse {
        try await runAndDecode(subcommandArgs: ["blocks", "--active", "--json", "--offline"], expectedKey: "blocks")
    }

    func fetchDaily(sinceYYYYMMDD: String) async throws -> DailyResponse {
        try await runAndDecode(
            subcommandArgs: ["daily", "--json", "--offline", "--since", sinceYYYYMMDD],
            expectedKey: "daily"
        )
    }

    /// Best-effort daily pricing cache refresh (no --offline). Failures are ignored.
    func refreshPricingCacheBestEffort() async {
        guard let resolution = await resolveIfNeeded() else { return }
        _ = await run(resolution: resolution, args: ["blocks", "--json"], timeout: 25)
    }

    private func runAndDecode<T: Decodable>(subcommandArgs: [String], expectedKey: String) async throws -> T {
        guard let resolution = await resolveIfNeeded() else {
            throw FetchError.ccusageUnavailable
        }
        let result = await run(resolution: resolution, args: subcommandArgs, timeout: 20)
        if result.timedOut {
            throw FetchError.timeout
        }
        guard let data = JSONExtractor.extractJSONObject(from: result.stdout, expectedKey: expectedKey) else {
            if result.exitCode != 0 {
                throw FetchError.processFailed(result.stderr)
            }
            throw FetchError.invalidOutput
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FetchError.invalidOutput
        }
    }

    private func resolveIfNeeded() async -> CCUsageResolution? {
        if let cached = cachedResolution {
            return cached
        }
        let resolved = await Task.detached(priority: .utility) {
            CCUsageResolver.resolve()
        }.value
        cachedResolution = resolved
        return resolved
    }

    private func run(resolution: CCUsageResolution, args: [String], timeout: TimeInterval) async -> ProcessRunResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let executable: String
        let fullArgs: [String]
        switch resolution {
        case .direct(let path):
            executable = path
            fullArgs = args
        case .npx(let npxPath):
            executable = npxPath
            fullArgs = ["-y", "ccusage@20"] + args
        }
        return await Task.detached(priority: .utility) {
            ProcessRunner.run(executable: executable, arguments: fullArgs, currentDirectory: home, timeout: timeout)
        }.value
    }
}
