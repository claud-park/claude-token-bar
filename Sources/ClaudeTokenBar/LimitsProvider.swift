import Foundation

// MARK: - Raw OAuth usage response (fields optional/defensive)

struct OAuthUsageWindow: Decodable, Sendable {
    let utilization: Double?
    let resets_at: String?
}

struct OAuthUsageResponse: Decodable, Sendable {
    let five_hour: OAuthUsageWindow?
    let seven_day: OAuthUsageWindow?
}

// MARK: - Normalized model

struct LimitsSnapshot: Codable, Sendable, Equatable {
    let sessionPercent: Double
    let sessionResetsAt: Date?
    let weeklyPercent: Double?
    let weeklyResetsAt: Date?
}

// MARK: - Provider

/// Fetches official usage-limit utilization (the same numbers Claude Code's
/// /usage screen shows) from the OAuth usage endpoint, authenticating with the
/// Claude Code credential in the login keychain. The token never leaves this
/// process and is never persisted or logged. Any failure returns nil — the UI
/// falls back to the block-reset countdown.
actor LimitsProvider {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func fetch() async -> LimitsSnapshot? {
        guard let token = await readAccessToken() else { return nil }
        var request = URLRequest(url: Self.usageURL, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(OAuthUsageResponse.self, from: data)
        else { return nil }

        return Self.map(decoded)
    }

    static func map(_ decoded: OAuthUsageResponse) -> LimitsSnapshot? {
        guard let session = decoded.five_hour?.utilization else { return nil }
        return LimitsSnapshot(
            sessionPercent: session,
            sessionResetsAt: parseDate(decoded.five_hour?.resets_at),
            weeklyPercent: decoded.seven_day?.utilization,
            weeklyResetsAt: parseDate(decoded.seven_day?.resets_at)
        )
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        if let date = SnapshotMapper.parseDate(string) { return date }
        // The endpoint emits microsecond fractions ("…T10:20:00.450756+00:00");
        // ISO8601DateFormatter only accepts milliseconds, so trim to 3 digits.
        let trimmed = string.replacingOccurrences(
            of: #"\.(\d{3})\d+"#,
            with: ".$1",
            options: .regularExpression
        )
        return SnapshotMapper.parseDate(trimmed)
    }

    /// Reads the Claude Code OAuth access token from the login keychain via
    /// /usr/bin/security (same ACL surface as Claude Code's own tooling).
    private func readAccessToken() async -> String? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
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
                  let raw = String(data: data, encoding: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                  let oauth = json["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String,
                  !token.isEmpty
            else { return nil }
            return token
        }.value
    }
}
