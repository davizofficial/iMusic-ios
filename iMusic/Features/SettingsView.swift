import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct RegionOption: Identifiable {
    let id: String
    let label: String
}

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var downloads: DownloadManager

    @State private var showExporter = false
    @State private var showImporter = false
    @State private var backupDoc: BackupDocument?
    @State private var showImportLink = false
    @State private var message: String?
    @State private var isTestingConnection = false
    @State private var directApiResult: String?
    @State private var youtubeBridgeResult: String?
    @State private var proxyApiResult: String?
    @State private var customProxyUrl: String = UserDefaults.standard.string(forKey: "custom_proxy_url") ?? "https://richmusic.vercel.app"

    private let regions: [RegionOption] = [
        RegionOption(id: "id-ID", label: "Indonesia"),
        RegionOption(id: "en-US", label: "Amerika Serikat"),
        RegionOption(id: "en-GB", label: "Inggris"),
        RegionOption(id: "ja-JP", label: "Jepang"),
    ]

    var body: some View {
        Form {
            Section("Unduhan") {
                Picker("Format", selection: downloadFormatBinding) {
                    Text("M4A (native)").tag("m4a")
                    Text("MP3 (konverter)").tag("mp3")
                }
                Text("M4A langsung dari sumbernya dan paling andal. MP3 memakai konverter pihak ketiga dan bisa gagal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pemutaran") {
                Toggle("SponsorBlock", isOn: Binding(
                    get: { player.sponsorBlockOn },
                    set: { player.setSponsorBlock($0) }
                ))
            }

            Section("Uji Koneksi (Proxy & API YT Music)") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("URL Proxy / Vercel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://richmusic.vercel.app", text: $customProxyUrl)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        .onChange(of: customProxyUrl) { newVal in
                            UserDefaults.standard.set(newVal, forKey: "custom_proxy_url")
                        }
                }

                Button {
                    Task { await testConnections() }
                } label: {
                    HStack {
                        if isTestingConnection {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Label(isTestingConnection ? "Sedang Menguji..." : "Uji Koneksi Sekarang", systemImage: "network")
                    }
                }
                .disabled(isTestingConnection)

                if let res = directApiResult {
                    HStack {
                        Text("InnerTube Direct")
                            .font(.caption)
                        Spacer()
                        Text(res)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(res.contains("✅") ? .green : .red)
                    }
                }

                if let res = youtubeBridgeResult {
                    HStack {
                        Text("Audio Player Engine")
                            .font(.caption)
                        Spacer()
                        Text(res)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(res.contains("✅") ? .green : .red)
                    }
                }

                if let res = proxyApiResult {
                    HStack {
                        Text("Server Proxy")
                            .font(.caption)
                        Spacer()
                        Text(res)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(res.contains("✅") ? .green : .red)
                    }
                }
            }

            Section("Wilayah") {
                Picker("Wilayah", selection: regionBinding) {
                    ForEach(regions) { r in
                        Text(LocalizedStringKey(r.label)).tag(r.id)
                    }
                }
                Text("Berlaku setelah app dibuka ulang.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Library") {
                Button { startBackup() } label: {
                    Label("Backup", systemImage: "square.and.arrow.up")
                }
                Button { showImporter = true } label: {
                    Label("Restore", systemImage: "square.and.arrow.down")
                }
                Button { showImportLink = true } label: {
                    Label("Impor dari Link", systemImage: "link")
                }
            }

            Section("Tentang") {
                HStack {
                    Text("Versi")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
                Text("iMusic — pemutar musik untuk penggunaan pribadi. Tidak berafiliasi dengan YouTube, Google, atau Apple.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Pengaturan")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $showExporter, document: backupDoc,
                      contentType: .json, defaultFilename: "imusic-backup") { _ in }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { handleImport($0) }
        .sheet(isPresented: $showImportLink) { ImportLinkSheet() }
        .alert("iMusic", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: Bindings

    private var downloadFormatBinding: Binding<String> {
        Binding(
            get: { library.settings.downloadFormat },
            set: { value in library.updateSettings { $0.downloadFormat = value } }
        )
    }

    private var regionBinding: Binding<String> {
        Binding(
            get: {
                let key = "\(AppConfig.hl)-\(AppConfig.gl)"
                return regions.contains { $0.id == key } ? key : "id-ID"
            },
            set: { value in
                let parts = value.split(separator: "-")
                guard parts.count == 2 else { return }
                AppConfig.hl = String(parts[0])
                AppConfig.gl = String(parts[1])
                UserDefaults.standard.set(AppConfig.hl, forKey: "region_hl")
                UserDefaults.standard.set(AppConfig.gl, forKey: "region_gl")
            }
        )
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: Actions

    private func startBackup() {
        guard let data = library.exportData() else {
            message = "Gagal membuat backup."
            return
        }
        backupDoc = BackupDocument(data: data)
        showExporter = true
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                try library.importData(Data(contentsOf: url))
                message = "Library berhasil dipulihkan."
            } catch {
                message = "Gagal restore: \(error.localizedDescription)"
            }
        case .failure(let error):
            message = "Gagal: \(error.localizedDescription)"
        }
    }

    private func testConnections() async {
        isTestingConnection = true
        directApiResult = "Menguji..."
        youtubeBridgeResult = "Menguji..."
        proxyApiResult = "Menguji..."

        // 1. YouTube Music Direct InnerTube ping
        do {
            let start = CFAbsoluteTimeGetCurrent()
            guard let url = URL(string: "https://music.youtube.com/generate_204") else { return }
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            let (_, resp) = try await URLSession.shared.data(for: req)
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                directApiResult = "✅ Terhubung (\(ms) ms)"
            } else {
                directApiResult = "⚠️ Status \((resp as? HTTPURLResponse)?.statusCode ?? 0)"
            }
        } catch {
            directApiResult = "❌ Gagal (\(error.localizedDescription))"
        }

        // 2. YouTube Audio Bridge Web engine ping
        do {
            let start = CFAbsoluteTimeGetCurrent()
            guard let url = URL(string: "https://www.youtube.com/iframe_api") else { return }
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            let (_, resp) = try await URLSession.shared.data(for: req)
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                youtubeBridgeResult = "✅ Siap (\(ms) ms)"
            } else {
                youtubeBridgeResult = "⚠️ Status \((resp as? HTTPURLResponse)?.statusCode ?? 0)"
            }
        } catch {
            youtubeBridgeResult = "❌ Gagal (\(error.localizedDescription))"
        }

        // 3. Proxy API ping
        let proxyBase = customProxyUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "https://richmusic.vercel.app"
            : customProxyUrl.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let start = CFAbsoluteTimeGetCurrent()
            let checkUrl = proxyBase.hasSuffix("/") ? "\(proxyBase)api/home" : "\(proxyBase)/api/home"
            guard let url = URL(string: checkUrl) ?? URL(string: proxyBase) else { return }
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            let (_, resp) = try await URLSession.shared.data(for: req)
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                proxyApiResult = "✅ Terhubung (\(ms) ms)"
            } else {
                proxyApiResult = "⚠️ Status \((resp as? HTTPURLResponse)?.statusCode ?? 0)"
            }
        } catch {
            proxyApiResult = "❌ Gagal (\(error.localizedDescription))"
        }

        isTestingConnection = false
    }
}

struct ImportLinkSheet: View {
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var busy = false
    @State private var message: String?
    @State private var artistId: String?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("https://music.youtube.com/…", text: $url)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                }
                Section {
                    Button { Task { await run() } } label: {
                        HStack {
                            if busy { ProgressView() }
                            Label("Impor", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(busy || url.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Impor dari Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { dismiss() }
                }
            }
            .background(
                NavigationLink(
                    destination: Group {
                        if let artistId { DetailView(browseId: artistId, kind: "artist") }
                    },
                    isActive: Binding(
                        get: { artistId != nil },
                        set: { if !$0 { artistId = nil } }
                    )
                ) {
                    EmptyView()
                }
                .hidden()
            )
        }
        .navigationViewStyle(.stack)
    }

    private func run() async {
        busy = true
        defer { busy = false }
        guard let resolved = MusicAPI.resolve(url: url) else {
            message = "Link tidak dikenali."
            return
        }
        switch resolved.kind {
        case "song":
            guard let videoId = resolved.videoId else { message = "Link lagu tidak valid."; return }
            if let next = try? await MusicAPI.next(videoId: videoId, playlistId: resolved.playlistId),
               let item = next.queue.first(where: { $0.videoId == videoId }) ?? next.queue.first {
                player.play(item.song)
                dismiss()
            } else {
                message = "Gagal memuat lagu."
            }
        case "artist":
            artistId = resolved.id
        default:
            guard let id = resolved.id else { message = "Link tidak valid."; return }
            if let page = try? await MusicAPI.browse(id: id, params: nil), !page.tracks.isEmpty {
                let name = page.header?.title ?? "Playlist Impor"
                let playlist = library.createPlaylist(name: name)
                for track in page.tracks { library.add(track.song, to: playlist.id) }
                message = "Diimpor \(page.tracks.count) lagu ke \"\(name)\"."
            } else {
                message = "Tidak ada lagu (mungkin playlist privat)."
            }
        }
    }
}
