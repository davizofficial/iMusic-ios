# iMusic — Implementation Plan

Aplikasi streaming musik iOS bergaya **Apple Music**, katalog **YouTube Music**.
**Tanpa server sendiri**: seluruh metadata diambil langsung dari InnerTube
YouTube Music, audio diputar native lewat `AVPlayer`. Dibuild jadi `.ipa` di
GitHub Actions, dipasang lewat sideload / TestFlight pribadi.

> Dokumen ini rencana, bukan kode aplikasi. File konkret yang sudah dibuat:
> `project.yml`, `.github/workflows/build-ipa.yml`, `Assets/AppIcon.svg`.

---

## 0. TL;DR — keputusan kunci

| Topik | Keputusan |
| --- | --- |
| Nama | **iMusic** (display name), target/skema `iMusic`, bundle `app.imusic.ios` |
| Deployment target | **iOS 16.0** (versi "16.8" tidak ada; 16.7.8 cuma patch keamanan). Target 16.0 mencakup semua perangkat 16.x |
| Bahasa / UI | Swift 5.9 + SwiftUI, dibuild Xcode 15 |
| Arsitektur | MVVM + `async/await`, `ObservableObject` (bukan `@Observable` — iOS 17) |
| Backend | **Tidak ada server.** Panggil `music.youtube.com/youtubei/v1/*` langsung dari app (native bebas CORS) |
| Metadata | Port logika `server.js` ke Swift; traversal JSON dinamis (`[String: Any]`), bukan Codable kaku |
| Audio | **`AVPlayer`** memutar stream audio hasil `/player` InnerTube → background, lock screen, AirPlay native |
| Fallback audio | WKWebView + YouTube IFrame, hanya kalau ekstraksi stream gagal |
| Library | File JSON di Application Support (kompatibel dengan backup web app) |
| Download | Offline `.m4a` (native, andal) + opsi `.mp3` via konverter langsung dari app |
| Dependency | **Nol** pihak ketiga. Hanya Apple framework |
| Build | GitHub Actions (macOS runner) → `.ipa` unsigned → re-sign sideload |

---

## 1. Kenapa "tanpa server" bisa (dan kenapa audio butuh pendekatan berbeda)

`server.js` di repo ini **hanya proxy**. Alasan keberadaannya:
- **CORS** — JavaScript browser tidak boleh memanggil `music.youtube.com` lintas-origin.
- Menormalkan bentuk JSON InnerTube yang berubah-ubah.
- Menyembunyikan `Origin`/`Referer` header.

Aplikasi native **tidak punya CORS**, jadi bisa memanggil InnerTube langsung
dengan `URLSession`. Server dihapus sepenuhnya. Ini artinya app bisa dibuka di
mana saja, kapan saja, tanpa infrastruktur.

**Tapi** metadata saja tidak cukup untuk memutar musik native. `server.js`
tidak pernah memberi URL audio — di web, audio diputar oleh YouTube IFrame.
Untuk **background audio + lock screen + download** (semua permintaanmu), kita
butuh URL stream audio asli:

- Endpoint InnerTube **`/player`** mengembalikan `streamingData.adaptiveFormats[]`
  yang berisi URL audio langsung.
- Dipanggil dengan konteks klien **`IOS`** (atau `ANDROID`), YouTube umumnya
  mengembalikan `url` polos tanpa `signatureCipher` — teknik yang sama yang
  dipakai yt-dlp dkk.
- Format audio: itag **139/140** = AAC dalam `.m4a` (didukung `AVPlayer`),
  itag 249–251 = Opus `.webm` (tidak didukung AVFoundation — dilewati).

Hasilnya: `AVPlayer` memutar `.m4a` langsung dari CDN YouTube → background
audio dan lock screen jadi native, tanpa trik keep-alive. Ini yang membuat
"mirip Apple Music asli" mungkin.

> Metadata (`browse`, `search`, `next`, `lyrics`) tetap pakai klien `WEB_REMIX`
> agar parsing sama persis dengan `server.js`. Hanya `/player` yang pakai klien `IOS`.

---

## 2. Arsitektur

```
iMusic
 ├─ App
 │   ├─ iMusicApp.swift            @main, inject environment objects
 │   └─ RootView.swift             TabView + MiniPlayer + fullScreen NowPlaying
 ├─ Core
 │   ├─ InnerTube/                  ← pengganti server.js
 │   │   ├─ InnerTubeClient.swift   URLSession, context WEB_REMIX/IOS, headers
 │   │   ├─ InnerTubeParser.swift   findAll/findFirst/text/thumbs (port dari server.js)
 │   │   ├─ MusicAPI.swift          home/charts/moods/search/suggest/next/related/browse
 │   │   ├─ StreamResolver.swift    /player → audio m4a URL + expiry
 │   │   ├─ LyricsAPI.swift         port strategi berlapis server.js
 │   │   ├─ SponsorBlock.swift      sponsor.ajay.app langsung
 │   │   └─ ResolveAPI.swift        parse link YT Music → route internal
 │   ├─ Models/                     MediaItem, Section, BrowsePage, Header, Lyrics, Song
 │   ├─ Player/
 │   │   ├─ PlayerEngine.swift      AVPlayer + AVQueuePlayer, AVPlayerItem
 │   │   ├─ PlayerModel.swift       ObservableObject: queue, index, shuffle, repeat, time
 │   │   ├─ NowPlayingCenter.swift  MPNowPlayingInfoCenter + MPRemoteCommandCenter
 │   │   ├─ AudioSession.swift      .playback, interupsi, route change
 │   │   └─ Crossfade.swift         (opsional, AVAudioEngine)
 │   ├─ Library/
 │   │   ├─ LibraryStore.swift      ObservableObject + JSON file
 │   │   └─ LibraryData.swift       Codable: favorites/playlists/saved/history/stats/settings
 │   ├─ Downloads/
 │   │   ├─ DownloadManager.swift   URLSession downloadTask, antrean, progres
 │   │   └─ MP3Converter.swift      opsi konverter (tanpa server)
 │   └─ Support/
 │       ├─ AppConfig.swift         region, bahasa, batas kualitas
 │       ├─ ImageLoader.swift       URLCache + NSCache
 │       ├─ ColorExtractor.swift    warna dominan artwork
 │       ├─ Formatters.swift, Haptics.swift
 ├─ Features/
 │   ├─ Home/  Search/  Browse/  Radio/
 │   ├─ Library/  Detail/
 │   ├─ NowPlaying/ (NowPlayingView, LyricsView, QueueView, MiniPlayer)
 │   └─ Downloads/DownloadsView.swift
 ├─ Components/ (SongRow, MediaCard, CarouselShelf, SectionHeader, ArtworkView, ...)
 ├─ Resources/  (Assets.xcassets, Info.plist)
 └─ project.yml
```

---

## 3. Port `server.js` → Swift (tanpa server)

Yang diport **hanya logika**, bukan HTTP server. Endpoint tetap sama, tapi
dipanggil `URLSession` langsung.

| Fungsi server.js | Padanan Swift |
| --- | --- |
| `findAll(obj,key)` / `findFirst` | fungsi rekursif pada `[String: Any]` |
| `text(runs/simpleText)` | `runsText(_:)` |
| `thumbs` / `upscale` | `bestThumbnail(_:)` + rewrite `=w544-h544` |
| `parseListItem` / `parseTwoRow` / `parseSections` | `InnerTubeParser` → `[MediaItem]` / `[Section]` |
| `endpointInfo` | `endpointInfo(_:)` → browseId/videoId/tipe |
| `browsePage` | `MusicAPI.browse(id:params:)` |
| `SEARCH_PARAMS` | konstanta params filter |
| `lyrics` (LRCLIB→YTM→NetEase→Textyl→ovh) | `LyricsAPI` strategi berlapis + `fetchTimeout` |

**Klien InnerTube (metadata):** `clientName: WEB_REMIX`, `clientVersion` mengikuti
yang dipakai server.js, `hl: "id"`, `gl: "ID"`. Header `Origin`/`Referer`
`music.youtube.com` disertakan untuk aman.

**Klien InnerTube (stream):** `clientName: IOS`, body `/player` dengan
`videoId`, `contentCheckOk: true`, `racyCheckOk: true`.

**Model longgar (sengaja):** InnerTube JSON terlalu bervariasi untuk Codable kaku.
`MediaItem` dengan semua field opsional + parser dinamis. Ini pilihan sadar demi
ketahanan; bukan utang teknis.

> Tidak ada CORS, tidak ada auth, tidak ada perubahan pada repo web. `server.js`
> tetap ada untuk versi web, dan bisa jadi cadangan kalau app butuh endpoint
> yang lebih berat di kemudian hari.

### 3.1 Cara kerja endpoint InnerTube (yang tadinya server)

Semua endpoint adalah
`POST https://music.youtube.com/youtubei/v1/<nama>?prettyPrint=false`
dengan body `{ context: { client: { clientName, clientVersion, hl, gl } }, ... }`
dan header `Content-Type`, `Origin`/`Referer: music.youtube.com`, `User-Agent`.
Respons adalah JSON dalam tanpa skema stabil → dibaca dengan traversal
`findAll(key)` / `findFirst(key)`, bukan Codable.

| Endpoint | Body penting | Yang diambil dari respons | Fungsi Swift |
| --- | --- | --- | --- |
| `browse` | `browseId` (`FEmusic_home`/`charts`/`moods_and_genres`; `MPRE…`=album; `UC…`/`MPLA…`=artist; `VL…`/`PL…`/`RDCLAK…`=playlist), `params`, `continuation` | `sectionListRenderer.contents`, `musicShelfRenderer`, `gridRenderer`, `musicResponsiveHeaderRenderer` | `MusicAPI.browse(id:params:)` |
| `search` | `query`, `params` (filter) | `musicShelfRenderer`, `itemSectionRenderer`, `musicCardShelfRenderer` | `MusicAPI.search(q:filter:)` |
| `music/get_search_suggestions` | `input` | `searchSuggestionRenderer.suggestion` | `MusicAPI.suggest(q:)` |
| `next` | `videoId` + `playlistId` (`RDAMVM<id>`), `isAudioOnly`, `tunerSettingValue`, `watchEndpointMusicSupportedConfigs` | `playlistPanelVideoRenderer` (antrean), `tabRenderer` (`MPLYt…` lirik, `MPTRt…` related) | `MusicAPI.next(videoId:playlistId:)` |
| `player` | `videoId`, `contentCheckOk`, `racyCheckOk`, **klien `IOS`** | `streamingData.adaptiveFormats[]`, `playabilityStatus` | `StreamResolver.resolve(videoId:)` |
| `browse` (lirik) | `browseId` = `MPLYt…` | `musicDescriptionShelfRenderer.description` | `LyricsAPI` |
| `browse` + `continuation` | `ctoken` | `sectionListContinuation.contents` | Home/Search memuat lebih banyak |

**Continuation:** server.js mengambil 3 continuation untuk Home. Port Swift harus
melakukan hal yang sama (`sectionListContinuation`), kalau tidak Home hanya berisi
beberapa rak pertama.

**Catatan kejujuran:** `/player` **bukan** endpoint di `server.js` — ini logika
baru dan titik paling rapuh. Hasilnya bisa berupa `url` polos (bagus),
`signatureCipher` (perlu descramble), atau `playabilityStatus` error
(age/region/DRM), dan belakangan YouTube makin sering meminta **PoToken**.
Karena itu semua diisolasi di `StreamResolver` agar bisa diperbaiki tanpa
menyentuh UI.

---

## 4. Pemutaran & background audio

**Rantai audio**
1. `StreamResolver` memanggil `/player` (klien IOS) → pilih itag audio AAC
   dengan bitrate tertinggi (140 = 128 kbps, atau 139). URL punya masa berlaku
   (~6 jam) → resolve ulang setiap track.
2. `PlayerEngine` membuat `AVPlayerItem(url:)`, set `AVPlayer`.
3. `AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)` +
   `setActive(true)`.
4. `UIBackgroundModes = [audio]` di Info.plist → audio jalan saat layar terkunci.
5. `NowPlayingCenter`: `MPNowPlayingInfoCenter` (judul, artis, durasi, artwork,
   `elapsed`, `rate`) + `MPRemoteCommandCenter` (play, pause, next, prev, seek,
   `changePlaybackPosition`). Artwork diambil dari thumbnail, di-cache.
6. Interupsi telepon/Siri & route change ditangani `AudioSession` (resume sesuai
   aturan Apple).

**Kenapa `AVPlayer`, bukan WKWebView (revisi dari rencana awal):**
- Background/lock screen andal tanpa trik keep-alive.
- Scrub presisi, AirPlay, `nowPlayingInfo` benar.
- Bisa **download** stream yang sama untuk offline.
- WKWebView tetap dipertahankan sebagai **fallback** jika `/player` mengembalikan
  `signatureCipher` dan descramble gagal.

**Engine: `AVPlayer` tunggal + maju manual** (bukan `AVQueuePlayer`).
Alasannya: fitur inti Apple Music adalah menyisipkan "Play Next" / menggeser
antrean di tengah pemutaran, dan `AVQueuePlayer` sangat kaku untuk mutasi itu.
Pendekatan: satu `AVPlayer`, satu `AVPlayerItem` aktif, `AVPlayerItem` berikutnya
di-preload (`prepare` + `isReadyToPlay`) untuk transisi cepat. `AVQueuePlayer`
hanya dipertimbangkan kalau nanti butuh gapless sejati (butuh HLS, bukan file tunggal).

**Kontrol playback:** play/pause/next/prev, seek, shuffle, repeat (off/all/one),
kecepatan 0.5×–2×, volume, crossfade (opsional, fase polish), sleep timer,
SponsorBlock auto-skip (dari `sponsor.ajay.app`), antrean "Play Next / Play Later"
ala Apple Music.

### 4.1 Error handling, offline, & ketahanan

Satu `enum AppError` + `ErrorPresenter` yang memetakan setiap error ke pesan
pengguna + aksi. Setiap layar punya 4 state eksplisit: **loading / empty / error /
loaded** (lihat §6).

| Penyebab | Deteksi | Pesan pengguna | Pemulihan |
| --- | --- | --- | --- |
| Tidak ada internet | `NWPathMonitor` + `URLError.notConnectedToInternet` | Banner "Tidak ada koneksi internet" | Mode offline: Library, Downloads, cache |
| Koneksi lambat / timeout | `URLError.timedOut` | "Koneksi lambat — mencoba lagi…" | Retry backoff 0.5s → 1.5s → 4s (maks 2) |
| Server sibuk / rate limit | HTTP 429, 5xx | "Server sedang sibuk, coba lagi" | Backoff + toast, tombol Retry |
| Lagu tak bisa diputar | `playabilityStatus.status` (UNPLAYABLE / LOGIN_REQUIRED / age / region) | "Lagu tidak tersedia — dilewati" | Auto `nextTrack`, tandai baris |
| Stream gagal di-resolve | tidak ada `adaptiveFormats` / `signatureCipher` gagal | "Tidak bisa memutar lagu ini" | Fallback WKWebView → jika gagal, skip |
| Respons tak terduga | field hilang / JSON aneh | (tidak terlihat) | Kembalikan partial, jangan crash, log |
| Lirik tidak ada | 200 tanpa lirik | Empty state "Lirik tidak tersedia" | **Bukan error**; tombol coba lagi |
| Unduhan gagal / disk penuh | error `URLSession` / `volumeAvailableCapacityForImportantUsage` | "Unduhan gagal" / "Ruang penyimpanan penuh" | Resume, retry, tandai di daftar |
| Dibatalkan pengguna | `NSURLErrorCancelled` | (diam) | — |

**Aturan umum**
- Semua request dibatalkan saat view hilang (simpan `Task`, panggil `.cancel()`).
- Jangan pernah menampilkan error mentah; selalu pesan manusia + aksi.
- Kegagalan satu lagu tidak boleh menghentikan antrean.
- Log terstruktur (endpoint, status, durasi) untuk diagnosis.

**Caching & offline**
- InnerTube memakai `POST`, jadi `URLCache` tidak mencachenya. Buat lapisan cache
  sendiri: in-memory + disk, key = `endpoint + body + region + client`.
  TTL: Home 10 mnt, Charts 30 mnt, moods 60 mnt, Detail 30 mnt, Search **tidak**.
- Thumbnail lewat `URLCache` (sudah mendukung GET).
- **Mode offline read-only:** Home dari cache, Library, Downloads, Detail dari
  cache tetap jalan. Search & streaming dimatikan dengan pesan jelas, bukan spinner
  tanpa akhir.
- Unduhan memakai `URLSession` background configuration agar lanjut saat app
  di-background, dan bisa di-resume setelah app dibuka lagi.

---

## 5. Download (offline + MP3)

**Unduhan native `.m4a` (default, andal)**
- `DownloadManager` mengambil URL audio dari `/player` (klien IOS) dan
  mengunduhnya dengan `URLSessionDownloadTask` ke `Documents/Downloads`.
- Nama file: `Artis - Judul.m4a` (sanitasi karakter).
- Muncul di tab **Library → Downloads**; diputar `AVPlayer` dari file lokal
  (tanpa jaringan) → benar-benar offline.
- **Download per playlist**: tombol "Download" di header album/playlist
  mengiterasi seluruh track dengan antrean + progres + batalkan.

**Opsi `.mp3`**
- Stream YouTube adalah AAC/`.m4a`, bukan MP3. Transcode di perangkat butuh
  ffmpeg/lame (berat & berlisensi) — tidak layak dibundel.
- Solusi tanpa server: panggil konverter pihak ketiga (loader.to, sama seperti
  web app) **langsung dari app**. Hasilnya `.mp3` asli, lalu disimpan ke
  Downloads. Sifatnya opsional, flaky, dan punya ToS sendiri.
- UI: toggle di Pengaturan → **"Format unduhan: M4A (native) / MP3 (konverter)"**.
  Default M4A. Jujur ke pengguna soal perbedaan keandalan.

> Di iOS tidak ada folder "Musik" bebas; file ada di container app dan bisa
> di-ekspor lewat Files/Share. Cukup untuk pemakaian pribadi.

---

## 6. Fitur — meniru Apple Music

**Navigasi:** `TabView` 5 tab ala Apple Music — Home (`house.fill`), Browse
(`square.grid.2x2`), Radio (`dot.radiowaves.left.and.right`), Library
(`square.stack`), Search (`magnifyingglass`). Tiap tab punya `NavigationStack`.

| Area | Fitur |
| --- | --- |
| Home | Greeting waktu, Recently Played (grid 2 kolom), shelf carousel: Mix for you, Liked, Playlists, Saved, rak YouTube Music |
| Browse | Grid kategori warna (moods), Charts |
| Radio | Stasiun dari charts/moods; mulai radio dari lagu mana pun |
| Library | Playlists, Favorites, Saved, History, Downloads, Stats. Buat/rename/hapus/urutkan |
| Search | `.searchable`, saran saat mengetik, recent, top result, hasil per tipe |
| Detail | Header artwork + gradient, Play/Shuffle/Save/Download, daftar lagu bernomor |
| Now Playing | Artwork besar beranimasi, scrubber, kontrol penuh, volume, AirPlay, queue, lirik |
| Lyrics | Sinkron, highlight + auto-scroll, tap baris = seek |
| Queue | "Playing Next" (user dulu, lalu radio), reorder drag, swipe hapus |
| Lain | Sleep timer, SponsorBlock, favorit, backup/restore JSON, share, import link |

### 6.1 Desain token (dipakai konsisten di seluruh app)

| Token | Nilai |
| --- | --- |
| Aksen | `#FA233B` (Apple Music red) untuk tombol play, tab aktif, highlight |
| Latar | sistem: `.systemBackground` / `.secondarySystemBackground`; mengikuti dark & light |
| Now Playing | **selalu gelap**, latar = artwork di-blur + gradient dari warna dominan artwork |
| Tipografi | SF (font sistem). Judul halaman `.largeTitle.bold()`, judul shelf `.title3.bold()`, baris lagu `.subheadline`, sekunder `.caption` — semua **Dynamic Type** |
| Grid | spacing kelipatan 8pt; padding layar 16pt; radius kartu 8pt, header 12pt |
| Bar | `.ultraThinMaterial` untuk tab bar & mini player (fallback solid bila Reduce Transparency) |
| Tap target | minimal 44×44pt |
| Ikon | SF Symbols saja (tanpa aset ikon tambahan) |

### 6.2 Layout tiap layar

- **Home:** judul besar ("Home"), Recently Played grid **2 kolom** (kartu horizontal
  artwork 56pt + judul), lalu shelf carousel (`LazyHStack`, kartu 160pt) dengan header
  "Lihat semua". Terakhir rak YouTube Music dari `/home`.
- **Browse:** grid kategori 2 kolom, kartu warna dari `/moods` + overlay simbol; di
  bawahnya Charts.
- **Radio:** kartu stasiun besar (artwork + nama + "Stasiun"), tap → mulai `/next`.
- **Library:** header + `Picker` segmented (Playlists/Favorites/Saved/History/
  Downloads/Stats). Playlists = grid 2 kolom. Favorites/History = daftar baris lagu.
- **Search:** `.searchable` di navigation bar; saat kosong tampilkan recent + Browse
  all; saat mengetik tampilkan saran; hasil dikelompokkan (Top result → Songs →
  Albums → Artists → Playlists).
- **Detail:** header besar (artwork 200pt, judul, subjudul, deskripsi) dengan
  background gradient warna dominan; tombol **Play / Shuffle / Download / Save**;
  daftar lagu bernomor, baris aktif berwarna aksen.
- **Now Playing:** artwork besar di tengah (radius 12, shadow), judul + artis,
  scrubber (`Slider` + waktu), kontrol: shuffle · prev · play/pause besar · next ·
  repeat, lalu baris bawah: volume · AirPlay · Lyrics · Queue. Tab kecil
  "Lirik / Antrean / Related" atau tombol yang membuka sheet.
- **MiniPlayer:** menempel di atas tab bar; artwork 44pt, judul/artis satu baris,
  play/pause + next, progress tipis di atasnya. Tap → Now Playing.

### 6.3 State tiap layar (wajib, bukan opsional)

| State | Tampilan |
| --- | --- |
| Loading | Skeleton/redacted (Home & Detail) atau spinner tengah (Search) |
| Empty | Ikon + judul + subteks + CTA (mis. "Cari lagu") |
| Error | Ikon + pesan manusia + tombol **Coba lagi** |
| Offline | Banner atas "Tidak ada koneksi" + konten dari cache bila ada |
| Loaded | Konten; `refreshable` untuk tarik-ulang |

Pagination (Home/Search) memuat continuation saat scroll mendekati bawah, dengan
footer spinner.

### 6.4 Navigasi & animasi (mirip Apple Music)

- `TabView` + satu `NavigationStack` per tab; state navigasi tidak direset saat
  pindah tab.
- Presentasi Now Playing: `fullScreenCover` dengan `matchedGeometryEffect` dari
  artwork mini player → artwork besar; **tarik ke bawah untuk menutup** (offset +
  spring), plus tombol chevron-down.
- Artwork membesar halus saat diputar; transisi crossfade antar layar.
- Mini player: progress tipis, animasi play/pause.
- Lirik: highlight `withAnimation(.easeInOut)`, auto-scroll ke baris aktif, baris
  lampau diredupkan.
- Haptics (`UIImpactFeedbackGenerator`) saat play/pause/seek/unduh selesai.

### 6.5 Aksesibilitas & lokalisasi

- VoiceOver: label jelas untuk setiap tombol ("Putar", "Berikutnya", "Antrean"),
  `.accessibilityValue` untuk scrubber ("1:23 dari 3:45"), grup baris lagu jadi satu
  elemen dengan aksi.
- **Reduce Motion:** matikan `matchedGeometryEffect` & auto-scroll lirik.
- **Reduce Transparency:** ganti material dengan warna solid.
- Dynamic Type sampai ukuran aksesibilitas terbesar tanpa teks terpotong.
- Lokalisasi lewat String Catalog: **Indonesia + Inggris**, ikut bahasa perangkat.
  `hl`/`gl` InnerTube mengikuti locale perangkat, bisa dioverride di Pengaturan.

---

## 7. Batasan iOS 16 — jangan pakai API ini

`@Observable`, `SwiftData`, `.containerRelativeFrame`, `PhaseAnimator`,
`.scrollPosition`, `NavigationLink(value:)` gaya 17 → hindari.
Pakai: `ObservableObject`/`@Published`, JSON file atau Core Data,
`GeometryReader`, `matchedGeometryEffect`, `NavigationStack`,
`.presentationDetents`, `ShareLink`, `Grid`, `AsyncImage`, `.searchable`,
`refreshable`.

---

## 8. State & penyimpanan

```
iMusicApp
 ├─ @StateObject AppModel
 │    ├─ InnerTubeClient / MusicAPI
 │    ├─ PlayerModel  ── PlayerEngine (AVPlayer) ── NowPlayingCenter
 │    ├─ LibraryStore (JSON file)
 │    └─ DownloadManager
 └─ RootView (TabView + MiniPlayer + fullScreenCover NowPlaying)
```

- `PlayerModel` pemilik tunggal antrean; UI hanya baca + panggil aksi.
- Antrean + posisi dipersist (`PlayerState`) → app restore setelah dibunuh.
- `LibraryStore` tulis JSON atomik tiap perubahan. Format **sama** dengan backup
  web app (`app: "rich-music"`, `version: 2`) agar bisa saling impor.

---

## 9. Ikon aplikasi

- Sumber: `Assets/AppIcon.svg`; PNG final sudah di-generate:
  `iMusic/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
  (1024×1024, RGB tanpa alpha, tanpa sudut membulat — iOS yang memask).
- `Contents.json` memakai mode **single size** (didukung Xcode 14+).
- Kalau ikon diubah: render ulang `Assets/AppIcon.svg` → 1024×1024 PNG, timpa file.
  ```bash
  rsvg-convert -w 1024 -h 1024 Assets/AppIcon.svg -o AppIcon-1024.png
  # alternatif: qlmanage -t -s 1024 -o . Assets/AppIcon.svg
  ```

---

## 10. Build `.ipa` di GitHub Actions

File: **`.github/workflows/build-ipa.yml`** (root repo). Alur:
XcodeGen generate project → `xcodebuild` (unsigned) → bungkus `Payload/` → artifact.
Skema `iMusic` didefinisikan eksplisit di `project.yml` (`schemes:`), jadi
`-scheme iMusic` pasti ada.

- Runner `macos-14` (Xcode 15.x). `CODE_SIGNING_ALLOWED=NO` → `.app` unsigned.
- Artifact: `iMusic-ipa` berisi `iMusic-unsigned.ipa`.
- **Kalau `MusicIOS/` dijadikan repo sendiri:** pindahkan `.github/` ke dalam
  `MusicIOS/` dan hapus `working-directory: MusicIOS` + ubah path artifact
  menjadi `iMusic-unsigned.ipa`.

### 10.1 Re-sign `.ipa` (wajib sebelum sideload)

`.ipa` dari Actions **unsigned** — tidak bisa langsung dipasang. Pilih salah satu:

1. **AltStore / SideStore** — import `.ipa`, otomatis di-sign dengan Apple ID-mu.
2. **Sideloadly** — drag `.ipa`, masukkan Apple ID, sign & install via USB.
3. **Feather / ESign** — sign di perangkat dengan sertifikat (butuh file `.p12` +
   `.mobileprovision`).
4. **Punya Apple Developer account** — ubah langkah build jadi `xcodebuild
   -exportArchive` dengan `ExportOptions.plist` (`method: development`/`ad-hoc`)
   + Secrets (sertifikat & provisioning) → hasil sudah ter-sign, bisa TestFlight.

> Untuk distribusi luas lewat App Store: tidak mungkin (lihat §14).

---

## 11. Fase pengerjaan

### Fase -1 — Spike audio (1 jam) ← lakukan SEBELUM semua
- [ ] Satu file Swift: panggil `/player` (klien IOS) untuk 1 videoId, cetak
      `streamingData.adaptiveFormats`, coba `AVPlayer(url:)` dan dengar suaranya.
- [ ] Catat: dapat `url` polos atau `signatureCipher`? Butuh PoToken?
- **Selesai bila:** audio terdengar dari `AVPlayer`. Kalau gagal → revisi arsitektur
  audio dulu, jangan lanjut Fase 0.

### Fase 0 — Fondasi (0.5–1 hari)
- [ ] `project.yml` → `xcodegen generate`; project build di simulator iOS 16.
- [ ] `InnerTubeClient` + `InnerTubeParser` + `MusicAPI` (home/search/next).
- [ ] Decode home versi in-app, tampilkan daftar judul (layar debug).
- **Selesai:** app jalan, data katalog tampil, **tanpa server**.

### Fase 1 — Audio native (2–3 hari) ← paling berisiko
- [ ] `StreamResolver` (`/player` klien IOS → URL m4a).
- [ ] `PlayerEngine` + `PlayerModel` + `AudioSession`.
- [ ] Background mode + `NowPlayingCenter` + remote commands.
- [ ] MiniPlayer + Now Playing dasar. Fallback WKWebView bila perlu.
- **Selesai:** lagu diputar native, lanjut saat layar terkunci, kontrol lock screen jalan.

### Fase 2 — Jelajah (2 hari)
- [ ] Home lengkap, Search (+suggest/recent/filter), Browse (moods), Charts, Detail.
- **Selesai:** telusuri katalog & putar dari tiap halaman.

### Fase 3 — Library (1.5 hari)
- [ ] `LibraryStore` JSON; Favorites/Playlists/Saved/History/Stats; Backup/Restore.
- **Selesai:** data bertahan; restore backup web app berhasil.

### Fase 4 — Lirik, antrean, download (2 hari)
- [ ] Lirik sinkron + tap-to-seek; Queue reorder; Related; SponsorBlock.
- [ ] `DownloadManager` offline `.m4a` + download per playlist; opsi MP3.
- **Selesai:** lirik mengikuti waktu; lagu bisa diunduh & diputar offline.

### Fase 5 — Polish (1.5 hari)
- [ ] Animasi Now Playing, haptics, warna dominan artwork, dark/light,
      Reduce Motion, Dynamic Type, empty/error state, pull-to-refresh.
- [ ] Ikon, launch screen, share sheet, import link.
- **Selesai:** terasa seperti Apple Music asli.

### Fase 6 — Build & uji (0.5 hari)
- [ ] Workflow GitHub Actions hijau → `.ipa` terunduh.
- [ ] Uji di perangkat fisik: background, lock screen, AirPlay, interupsi, offline.

Total: **~10–12 hari kerja** satu orang.

---

## 12. Testing

- **Unit (XCTest):** decode fixture JSON asli tiap endpoint → model tak crash
  saat field hilang; uji `StreamResolver` memilih itag AAC tertinggi.
- **Manual (wajib):** background/lock screen, interupsi telepon/Siri, ganti rute
  audio, koneksi lambat/offline, download besar, batalkan download.
- `xcodebuild test` di Mac.

---

## 13. Risiko & mitigasi

| Risiko | Dampak | Mitigasi |
| --- | --- | --- |
| `/player` mengembalikan `signatureCipher` (URL terenkripsi) | Tinggi | Pakai klien `IOS`/`ANDROID`; fallback WKWebView; resolver mudah diganti |
| YouTube ubah skema tanpa pemberitahuan | Tinggi | Metadata lewat parser dinamis; audio terisolasi di `StreamResolver`; rilis update cepat |
| Throttling `n`-param | Sedang | Klien IOS umumnya lolos; kalau tidak, fallback WebView |
| Ads ikut terputar (mode WebView) | Sedang | Hanya terjadi di fallback; mode native bebas ads |
| ToS YouTube / App Store | Tinggi | **Bukan untuk App Store**; sideload/TestFlight pribadi; disclaimer "tidak berafiliasi" |
| Nama "iMusic" | Rendah | Aman untuk pemakaian pribadi; ganti bila akan didistribusikan luas |
| Transcode MP3 di perangkat | Sedang | Default M4A native; MP3 lewat konverter, opsional & dijelaskan |
| Duplikasi logika parsing vs server.js | Rendah | Diterima; tidak perlu sinkron terus-menerus |
| Perubahan format backup web | Rendah | `LibraryData` punya `version` + fungsi migrasi (v2→vN); tolak file versi lebih baru dengan pesan jelas |

---

## 14. Legal & distribusi

- **Tidak untuk App Store**: memutar katalog YouTube tanpa izin resmi akan
  ditolak. Target: sideload (AltStore/Sideloadly/Feather), TestFlight pribadi,
  atau build sendiri.
- Cantumkan "Tidak berafiliasi dengan YouTube, Google, atau Apple" di About.
- Jangan pakai nama/logo Apple Music; aplikasi bernama **iMusic**.

---

## 15. Setup di Mac (mulai implementasi)

Repo saat ini sudah punya kerangka yang bisa di-build:
`project.yml`, `iMusic/App/iMusicApp.swift` + `RootView.swift` (placeholder),
`Resources/Assets.xcassets/AppIcon.appiconset/` (ikon 1024 PNG),
dan `.github/workflows/build-ipa.yml`.

```bash
brew install xcodegen
cd MusicIOS
xcodegen generate
open iMusic.xcodeproj      # pilih iOS 16 simulator, Run (placeholder "iMusic")
```

Build `.ipa` otomatis: push ke GitHub → tab **Actions** → unduh artifact
`iMusic-ipa` → re-sign dengan alat sideload (§10.1).

Langkah implementasi pertama sebenarnya adalah **Fase -1 (spike audio)**, bukan UI.

---

## 16. Yang sengaja TIDAK dikerjakan di v1

- Sinkronisasi cloud / akun.
- Layout sidebar iPad, Stage Manager, CarPlay, Widget, Live Activity.
- Visualizer audio real-time.
- Crossfade lanjutan via `AVAudioEngine` (masuk hanya jika diminta).
- Transcode MP3 on-device (bundling ffmpeg ditolak demi ukuran & lisensi).

---

## 17. Status implementasi saat ini

Kode inti sudah di-generate (36 file Swift) — arsitektur lengkap dan saling
terhubung. **Belum pernah di-compile** karena lingkungan kerja tidak punya
Xcode; verifikasi hanya bisa di Mac / GitHub Actions.

**Sudah ada**
- `InnerTubeClient` + `InnerTubeParser` + `MusicAPI` (home, charts, moods,
  search, suggest, next, related, browse, resolve) — tanpa server.
- Cache InnerTube dua lapis (memori + disk, TTL per endpoint) + fallback
  read-only offline saat jaringan gagal.
- `StreamResolver` (`/player` klien IOS → URL AAC) — **wajib di-spike**.
- `PlayerEngine` (AVPlayer) + `PlayerModel` (antrean, shuffle, repeat, speed,
  sleep timer, SponsorBlock, radio) + `AudioSessionManager` + `NowPlayingCenter`.
- Persistensi antrean + posisi (`PlayerState`) → dipulihkan paused setelah app
  dibunuh.
- `LibraryStore` (favorit, playlist, tersimpan, riwayat, statistik, backup/restore
  kompatibel web) + decoding toleran.
- `LyricsAPI` (YouTube Music + LRCLIB) dan model lirik sinkron.
- `DownloadManager` (offline `.m4a`) + `MP3Converter` (opsional).
- `NetworkMonitor` + banner offline + retry backoff.
- Haptics, VoiceOver (label/value), Reduce Motion, Reduce Transparency,
  Dynamic Type.
- Lokalisasi String Catalog (125 kunci; sumber `id`, terjemahan `en`).
- UI: Home, Jelajahi (moods+charts), Radio, Cari, Library, Detail
  (album/playlist/artis), Now Playing (lirik, antrean reorder, terkait, speed,
  sleep timer), MiniPlayer, Settings/About, Download, impor link, komponen bersama.

**Belum ada (sesuai fase berikutnya)**
- Fallback WKWebView bila `/player` mengembalikan `signatureCipher` (dan
  penanganan PoToken).
- Animasi `matchedGeometryEffect` mini player → Now Playing.
- iPad layout (sengaja di luar v1).

**Langkah berikutnya:** Fase -1 (spike `/player`) di Mac/perangkat fisik sebelum
menyentuh apa pun lagi.
