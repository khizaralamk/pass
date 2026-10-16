import UIKit
import UserNotifications

/// Hosts the notification-center delegate so a tapped notification can be routed (spec §15) and foreground alerts are shown.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by the composition root; receives the payload of a tapped notification. A tap that arrives earlier
    /// (cold launch from a notification) is kept and replayed once the handler is installed.
    @MainActor static var notificationTapHandler: (@MainActor ([AnyHashable: Any]) -> Void)? {
        didSet {
            if let pending = pendingNotification, let handler = notificationTapHandler {
                pendingNotification = nil
                handler(pending)
            }
        }
    }
    @MainActor private static var pendingNotification: [AnyHashable: Any]?

    /// Receives the APNs device token (hex). Installed by the composition root only when a real backend is configured;
    /// a token that arrives before that is kept and replayed.
    @MainActor static var deviceTokenHandler: (@MainActor (String) -> Void)? {
        didSet {
            if let pending = pendingDeviceToken, let handler = deviceTokenHandler {
                pendingDeviceToken = nil
                handler(pending)
            }
        }
    }
    @MainActor private static var pendingDeviceToken: String?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        if let handler = AppDelegate.deviceTokenHandler { handler(hex) } else { AppDelegate.pendingDeviceToken = hex }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected on the simulator and without the Push capability; the app keeps working without pushes.
        #if DEBUG
        print("APNs registration failed: \(error.localizedDescription)")
        #endif
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        await MainActor.run {
            if let handler = AppDelegate.notificationTapHandler { handler(info) } else { AppDelegate.pendingNotification = info }
        }
    }
}
