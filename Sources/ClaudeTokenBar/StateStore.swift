import Foundation

struct ProjectFileRecord: Codable, Hashable, Sendable, Comparable {
    let path: String
    let modifiedAt: TimeInterval
    let size: Int64

    static func < (lhs: ProjectFileRecord, rhs: ProjectFileRecord) -> Bool {
        if lhs.path != rhs.path { return lhs.path < rhs.path }
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt < rhs.modifiedAt }
        return lhs.size < rhs.size
    }
}

struct ProjectSignature: Codable, Equatable, Sendable {
    let files: [ProjectFileRecord]
}

struct StoredState: Codable, Sendable {
    var snapshot: UsageSnapshot
    var signature: ProjectSignature?
    var pricingRefreshDay: String?
}

actor StateStore {
    private let stateURL: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = support.appendingPathComponent("ClaudeTokenBar", isDirectory: true)
        self.stateURL = directory.appendingPathComponent("state.json")
    }

    func load() -> StoredState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder.appDecoder.decode(StoredState.self, from: data)
        else {
            return StoredState(snapshot: .empty, signature: nil, pricingRefreshDay: nil)
        }
        return state
    }

    func save(_ state: StoredState) {
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.appEncoder.encode(state)
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            // Persistence failure should not affect the menu bar app's live display.
        }
    }
}

extension JSONDecoder {
    static var appDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var appEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
