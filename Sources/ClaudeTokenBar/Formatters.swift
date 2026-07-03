import Foundation

/// Pure, side-effect-free display formatting helpers.
enum Formatters {

    /// Token counts: `999`, `1.0K`, `12.3K`, `1.2M` (1 decimal for anything >= 1000).
    static func tokens(_ count: Int) -> String {
        let magnitude = abs(count)
        let sign = count < 0 ? "-" : ""
        if magnitude < 1_000 {
            return "\(count)"
        } else if magnitude < 1_000_000 {
            return sign + String(format: "%.1fK", Double(magnitude) / 1_000)
        } else {
            return sign + String(format: "%.1fM", Double(magnitude) / 1_000_000)
        }
    }

    /// Cost: `$12.34` (2dp). `<$0.01` for tiny nonzero amounts.
    static func cost(_ amount: Double) -> String {
        if amount != 0 && abs(amount) < 0.01 {
            return "<$0.01"
        }
        return String(format: "$%.2f", amount)
    }

    /// Countdown between two instants, e.g. `2h 41m` / `41m`. Never negative.
    static func countdown(from now: Date, to end: Date) -> String {
        let totalSeconds = max(0, Int(end.timeIntervalSince(now)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Local wall-clock time with seconds, e.g. `11:42:03`.
    static func time(_ date: Date) -> String {
        makeTimeFormatter("HH:mm:ss").string(from: date)
    }

    /// Local wall-clock time without seconds, e.g. `14:00`.
    static func resetTime(_ date: Date) -> String {
        makeTimeFormatter("HH:mm").string(from: date)
    }

    private static func makeTimeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }
}
