import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var net = NetworkMonitor.shared
    @State private var selection = 0
    @State private var showNowPlaying = false

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
            BrowseView()
                .tabItem { Label("Jelajahi", systemImage: "square.grid.2x2.fill") }
                .tag(1)
            RadioView()
                .tabItem { Label("Radio", systemImage: "dot.radiowaves.left.and.right") }
                .tag(2)
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack.fill") }
                .tag(3)
            SearchView()
                .tabItem { Label("Cari", systemImage: "magnifyingglass") }
                .tag(4)
        }
        .overlay(alignment: .bottom) {
            if player.current != nil, !showNowPlaying {
                MiniPlayer { showNowPlaying = true }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 56)
            }
        }
        .overlay(alignment: .top) {
            if !net.isOnline {
                Label("Tidak ada koneksi internet", systemImage: "wifi.slash")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .background(
                        Group {
                            if reduceTransparency {
                                Color(.secondarySystemBackground)
                            } else {
                                Color.clear.background(.ultraThinMaterial)
                            }
                        }
                    )
                    .clipShape(Capsule())
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: net.isOnline)
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
        .onAppear {
            player.setupRemoteCommandsIfNeeded()
        }
    }
}
