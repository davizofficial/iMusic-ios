import SwiftUI

@main
@MainActor
struct iMusicApp: App {
    @StateObject private var player = PlayerModel()
    @StateObject private var library = LibraryStore.shared
    @StateObject private var downloads = DownloadManager.shared

    init() {
        if let hl = UserDefaults.standard.string(forKey: "region_hl") { AppConfig.hl = hl }
        if let gl = UserDefaults.standard.string(forKey: "region_gl") { AppConfig.gl = gl }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(player)
                .environmentObject(library)
                .environmentObject(downloads)
                .tint(Theme.accent)
        }
    }
}
