import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }
}

@main
struct iMusicApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var player = PlayerModel()

    init() {
        if let hl = UserDefaults.standard.string(forKey: "region_hl") { AppConfig.hl = hl }
        if let gl = UserDefaults.standard.string(forKey: "region_gl") { AppConfig.gl = gl }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(player)
                .environmentObject(LibraryStore.shared)
                .environmentObject(DownloadManager.shared)
                .tint(Theme.accent)
        }
    }
}
