import Foundation
import CoreServices

/// Watches ~/.claude/projects for transcript changes. Primary trigger is an
/// FSEventStream (kernel-pushed, ~3s coalescing latency, zero cost when idle)
/// backed by a slow (300s) safety poll in case events are dropped. If FSEvents
/// fails to start, falls back to the original 15s poll. Either path funnels
/// through the signature gate so `onChange` only fires on real jsonl changes.
final class ProjectsWatcher: @unchecked Sendable {
    private let projectsURL: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.claudetokenbar.projects-watcher")
    private var stream: FSEventStreamRef?
    private var timer: DispatchSourceTimer?
    private var lastSignature: ProjectSignature?

    init(projectsURL: URL, onChange: @escaping @Sendable () -> Void) {
        self.projectsURL = projectsURL
        self.onChange = onChange
    }

    func start() {
        queue.async {
            guard self.timer == nil, self.stream == nil else { return }
            self.lastSignature = Self.computeSignature(at: self.projectsURL)
            let fsEventsLive = self.startFSEventStream()
            // 300s safety net when FSEvents is live (it's the primary trigger
            // and rarely misses); 15s primary poll otherwise.
            self.startTimer(interval: fsEventsLive ? 300 : 15)
        }
    }

    func stop() {
        queue.async {
            self.teardownLocked()
        }
    }

    deinit {
        // No external refs remain, so touching state directly is safe here.
        teardownLocked()
    }

    private func teardownLocked() {
        timer?.cancel()
        timer = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func startFSEventStream() -> Bool {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            // Delivered on `queue` via FSEventStreamSetDispatchQueue below.
            Unmanaged<ProjectsWatcher>.fromOpaque(info).takeUnretainedValue().poll()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [projectsURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            3.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)
        ) else { return false }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }
        self.stream = stream
        return true
    }

    private func startTimer(interval: TimeInterval) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // Generous leeway lets the OS coalesce this wakeup with other
        // scheduled system activity instead of waking the CPU on the dot.
        let leeway = DispatchTimeInterval.seconds(Int(interval / 3))
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: leeway)
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        self.timer = timer
        timer.resume()
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
