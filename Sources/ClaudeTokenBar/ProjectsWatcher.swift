import Foundation

final class ProjectsWatcher: @unchecked Sendable {
    private let projectsURL: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.claudetokenbar.projects-watcher")
    private var timer: DispatchSourceTimer?
    private var lastSignature: ProjectSignature?

    init(projectsURL: URL, onChange: @escaping @Sendable () -> Void) {
        self.projectsURL = projectsURL
        self.onChange = onChange
    }

    func start() {
        queue.async {
            guard self.timer == nil else { return }
            self.lastSignature = Self.computeSignature(at: self.projectsURL)
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 15, repeating: 15)
            timer.setEventHandler { [weak self] in
                self?.poll()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
        }
    }

    private func poll() {
        let signature = Self.computeSignature(at: projectsURL)
        if signature != lastSignature {
            lastSignature = signature
            onChange()
        }
    }

    static func computeSignature(at projectsURL: URL, now: Date = Date()) -> ProjectSignature {
        let cutoff = now.addingTimeInterval(-26 * 60 * 60)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return ProjectSignature(files: [])
        }

        var records: [ProjectFileRecord] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= cutoff
            else { continue }

            records.append(ProjectFileRecord(
                path: fileURL.path,
                modifiedAt: modifiedAt.timeIntervalSince1970,
                size: Int64(values.fileSize ?? 0)
            ))
        }
        return ProjectSignature(files: records.sorted())
    }
}
