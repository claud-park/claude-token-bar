import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private var refreshCoordinator: RefreshCoordinator?
    private var watcher: ProjectsWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let projectsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
        let statusController = StatusItemController()
        let coordinator = RefreshCoordinator(
            provider: CCUsageProvider(),
            store: StateStore(),
            projectsURL: projectsURL
        ) { snapshot in
            statusController.render(snapshot)
        }

        statusController.setRefreshAction {
            coordinator.refreshNow(force: true)
        }

        let watcher = ProjectsWatcher(projectsURL: projectsURL) {
            Task { @MainActor in
                coordinator.scheduleDebouncedRefresh()
            }
        }

        self.statusController = statusController
        self.refreshCoordinator = coordinator
        self.watcher = watcher

        coordinator.start()
        watcher.start()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        watcher?.stop()
        refreshCoordinator?.stop()
    }

    @objc private func didWake() {
        refreshCoordinator?.refreshNow(force: true)
    }
}
