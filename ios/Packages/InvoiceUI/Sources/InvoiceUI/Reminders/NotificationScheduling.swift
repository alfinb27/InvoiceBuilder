import UserNotifications

/// Abstracts `UNUserNotificationCenter` so reminder scheduling is injectable (`AppDependencies`) and testable.
/// `UNUserNotificationCenter.current()` crashes when touched from a bare test host with no real app bundle (SPM
/// unit test targets), so tests and previews must never reach `SystemNotificationScheduler`.
public protocol NotificationScheduling: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async
    func removeAllPending()
    func add(_ request: UNNotificationRequest) async
}

/// The real notification center. Only `AppDependencies.live()` uses this.
public struct SystemNotificationScheduler: NotificationScheduling {
    public init() {}

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    public func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func removeAllPending() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    public func add(_ request: UNNotificationRequest) async {
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// Never touches the OS: the default for `AppDependencies.inMemory`/`forLaunch` (tests, previews, UI-test runs
/// that should never show a real permission prompt).
public struct NoOpNotificationScheduler: NotificationScheduling {
    public init() {}
    public func authorizationStatus() async -> UNAuthorizationStatus { .notDetermined }
    public func requestAuthorization() async {}
    public func removeAllPending() {}
    public func add(_ request: UNNotificationRequest) async {}
}
