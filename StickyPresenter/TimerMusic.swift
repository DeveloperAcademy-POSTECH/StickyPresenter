import SwiftUI
import AVFoundation
import AppKit

// MARK: - Music Mood
// 분위기별로 폴더를 나눠, 사용자가 직접 넣은 음원을 골라 틀 수 있게 한다.
// 폴더명은 Finder에서 순서대로 보이도록 숫자 접두사를 붙인 영문 고정값.
enum MusicMood: String, CaseIterable, Identifiable {
    case focus      // 집중 — 잔잔한 반복, 가사 없음
    case calm       // 차분 — 앰비언트/피아노
    case jazz       // 재즈 — 카페 재즈, 보사노바
    case upbeat     // 활기 — 가벼운 팝/펑크

    var id: String { rawValue }

    /// 디스크상의 폴더명
    var folderName: String {
        switch self {
        case .focus:  return "1-Focus"
        case .calm:   return "2-Calm"
        case .jazz:   return "3-Jazz"
        case .upbeat: return "4-Upbeat"
        }
    }

    var label: String {
        switch self {
        case .focus:  return "Focus"
        case .calm:   return "Calm"
        case .jazz:   return "Jazz"
        case .upbeat: return "Upbeat"
        }
    }

    var icon: String {
        switch self {
        case .focus:  return "brain.head.profile"
        case .calm:   return "moon.stars.fill"
        case .jazz:   return "music.quarternote.3"
        case .upbeat: return "bolt.fill"
        }
    }

    var tint: Color {
        switch self {
        case .focus:  return Color(red: 0.35, green: 0.55, blue: 0.95)
        case .calm:   return Color(red: 0.55, green: 0.45, blue: 0.85)
        case .jazz:   return Color(red: 0.85, green: 0.55, blue: 0.25)
        case .upbeat: return Color(red: 0.95, green: 0.40, blue: 0.45)
        }
    }

    /// 툴팁·안내문에 쓰는 설명
    var hint: String {
        switch self {
        case .focus:  return "Steady instrumentals — deep work and rehearsal"
        case .calm:   return "Ambient and solo piano — winding down before a talk"
        case .jazz:   return "Café jazz and bossa nova — relaxed, conversational rooms"
        case .upbeat: return "Light pop and funk — warm-ups and breaks"
        }
    }
}

// MARK: - Music Library
// 앱 컨테이너 안의 Music 폴더를 분위기별로 훑어 재생 목록을 만든다.
// 음원은 앱에 번들하지 않는다 — 사용자가 직접 소유·확보한 파일만 재생한다.
final class MusicLibrary: ObservableObject {
    static let shared = MusicLibrary()

    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac"
    ]

    @Published private(set) var tracks: [MusicMood: [URL]] = [:]

    private init() {
        prepareFolders()
        reload()
    }

    /// ~/Library/Application Support/StickyPresenter/Music
    /// (샌드박스에서는 앱 컨테이너 하위로 자동 해석된다)
    var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("StickyPresenter/Music", isDirectory: true)
    }

    func folderURL(for mood: MusicMood) -> URL {
        rootURL.appendingPathComponent(mood.folderName, isDirectory: true)
    }

    /// 분위기별 폴더와 안내문을 만든다. 이미 있으면 건드리지 않는다.
    func prepareFolders() {
        let fm = FileManager.default
        for mood in MusicMood.allCases {
            try? fm.createDirectory(at: folderURL(for: mood), withIntermediateDirectories: true)
        }
        let readme = rootURL.appendingPathComponent("README.txt")
        if !fm.fileExists(atPath: readme.path) {
            try? Self.readmeText.write(to: readme, atomically: true, encoding: .utf8)
        }
        // 한글 안내문을 쓰던 초기 버전의 잔여 파일 정리
        try? fm.removeItem(at: rootURL.appendingPathComponent("읽어주세요.txt"))
    }

    func reload() {
        var found: [MusicMood: [URL]] = [:]
        for mood in MusicMood.allCases {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: folderURL(for: mood),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            found[mood] = urls
                .filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        tracks = found
    }

    func tracks(for mood: MusicMood) -> [URL] { tracks[mood] ?? [] }

    /// Finder에서 해당 분위기 폴더를 연다.
    func revealInFinder(_ mood: MusicMood) {
        prepareFolders()
        NSWorkspace.shared.open(folderURL(for: mood))
    }

    /// 폴더에 남겨두는 안내문 — 어떤 파일을 어디서 구할지 알려준다.
    private static let readmeText = """
    StickyPresenter — Timer Background Music

    Drop audio files into the mood folders below and they show up in the music bar
    at the bottom of the timer panel.

    Supported formats: mp3, m4a, aac, wav, aiff, caf, flac

      1-Focus    Steady instrumentals — deep work and rehearsal
      2-Calm     Ambient and solo piano — winding down before a talk
      3-Jazz     Cafe jazz and bossa nova — relaxed, conversational rooms
      4-Upbeat   Light pop and funk — warm-ups and breaks

    After adding files, hit "Refresh" in the music bar's ... menu.

    ---- Where to get free music ----

    These sites offer downloads explicitly cleared for reuse. Each track states its
    own license (CC0, CC-BY, attribution required, etc.) on its download page --
    check it before you ship anything.

      YouTube Audio Library   studio.youtube.com -> Audio Library
                              Google's own library. Filter by genre and mood,
                              download as mp3 directly.
      Pixabay Music           pixabay.com/music/         mostly no attribution needed
      Free Music Archive      freemusicarchive.org/      filter by CC license
      Internet Archive        archive.org/details/audio  public domain and CC audio
      ccMixter                ccmixter.org/              strong on remixes and jazz
      Incompetech             incompetech.com/music/     CC-BY, fine-grained moods
      Chosic                  chosic.com/free-music/     browse by mood tag
      Bensound                bensound.com/              free tier needs attribution

    ---- A note on YouTube ----

    Don't drop audio ripped from YouTube videos in here. Most of it is copyrighted,
    and extracting it breaks YouTube's Terms of Service. Use the download buttons on
    the sites above instead.
    """
}

// MARK: - Music Player
// AVAudioPlayer 한 개를 재사용하며 곡이 끝나면 다음 곡으로 넘긴다.
// 시작·정지는 항상 페이드를 거쳐 발표 중 갑작스러운 소리 변화를 막는다.
final class MusicPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = MusicPlayer()

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTitle: String?

    @Published var mood: MusicMood {
        didSet {
            guard mood != oldValue else { return }
            UserDefaults.standard.set(mood.rawValue, forKey: Keys.mood)
            // 재생 중이면 새 분위기로 즉시 갈아탄다
            if isPlaying { rebuildQueue(); advance(fadeIn: true) }
        }
    }

    @Published var volume: Double {
        didSet {
            UserDefaults.standard.set(volume, forKey: Keys.volume)
            applyVolume()
        }
    }

    /// 켜두면 타이머가 돌 때 자동 재생, 모두 멈추면 자동 정지
    @Published var followsTimer: Bool {
        didSet {
            UserDefaults.standard.set(followsTimer, forKey: Keys.followsTimer)
            if followsTimer { syncWithTimers() }
        }
    }

    private enum Keys {
        static let mood = "music.mood"
        static let volume = "music.volume"
        static let followsTimer = "music.followsTimer"
    }

    private var player: AVAudioPlayer?
    private var queue: [URL] = []
    private var fadeTimer: Foundation.Timer?
    /// 페이드용 배율(0...1). 실제 출력 = volume × fadeGain
    private var fadeGain: Double = 1

    private override init() {
        let d = UserDefaults.standard
        mood = MusicMood(rawValue: d.string(forKey: Keys.mood) ?? "") ?? .focus
        volume = d.object(forKey: Keys.volume) as? Double ?? 0.35
        followsTimer = d.object(forKey: Keys.followsTimer) as? Bool ?? true
        super.init()
    }

    // MARK: - Public control

    func toggle() {
        isPlaying ? stop() : start()
    }

    /// 재생 시작. 해당 분위기에 곡이 없으면 아무 일도 하지 않는다.
    func start() {
        guard !MusicLibrary.shared.tracks(for: mood).isEmpty else { return }
        if player == nil || queue.isEmpty { rebuildQueue() }
        if player == nil {
            advance(fadeIn: true)
        } else {
            player?.play()
            fade(to: 1)
        }
        isPlaying = true
    }

    /// 페이드아웃 후 정지. 위치는 유지해 다시 켜면 이어서 재생된다.
    func stop() {
        isPlaying = false
        fade(to: 0) { [weak self] in
            self?.player?.pause()
        }
    }

    func skip() {
        guard isPlaying else { return }
        advance(fadeIn: true)
    }

    /// 라이브러리 갱신 후 현재 분위기에 곡이 사라졌으면 정지한다.
    func reloadLibrary() {
        MusicLibrary.shared.reload()
        if MusicLibrary.shared.tracks(for: mood).isEmpty {
            hardStop()
        } else if isPlaying {
            rebuildQueue()
        }
    }

    /// 타이머 실행 상태에 맞춰 재생/정지를 맞춘다. 타이머 상태가 바뀔 때마다 호출된다.
    func syncWithTimers() {
        guard followsTimer else { return }
        let anyRunning = NoteManager.shared.timerListManager.entries.contains { $0.isRunning }
        if anyRunning {
            if !isPlaying { start() }
        } else if isPlaying {
            stop()
        }
    }

    // MARK: - Queue

    /// 현재 분위기의 곡을 섞어 대기열을 만든다. 직전 곡이 연달아 나오지 않도록 앞머리를 피한다.
    private func rebuildQueue() {
        var shuffled = MusicLibrary.shared.tracks(for: mood).shuffled()
        if shuffled.count > 1, let current = player?.url, shuffled.first == current {
            shuffled.swapAt(0, shuffled.count - 1)
        }
        queue = shuffled
    }

    /// 대기열에서 다음 곡을 꺼내 재생한다. 비었으면 다시 채운다.
    private func advance(fadeIn: Bool) {
        if queue.isEmpty { rebuildQueue() }
        guard !queue.isEmpty else { hardStop(); return }

        let url = queue.removeFirst()
        guard let next = try? AVAudioPlayer(contentsOf: url) else {
            // 손상되거나 지원하지 않는 파일 — 건너뛰고 다음 곡으로
            advance(fadeIn: fadeIn)
            return
        }

        player?.stop()
        next.delegate = self
        next.prepareToPlay()
        fadeGain = fadeIn ? 0 : 1
        next.volume = Float(volume * fadeGain)
        next.play()

        player = next
        currentTitle = url.deletingPathExtension().lastPathComponent
        if fadeIn { fade(to: 1) }
    }

    /// 페이드 없이 즉시 완전 정지 — 재생할 곡이 없어진 경우
    private func hardStop() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        player?.stop()
        player = nil
        queue = []
        currentTitle = nil
        isPlaying = false
    }

    // MARK: - Fade

    private func applyVolume() {
        player?.volume = Float(volume * fadeGain)
    }

    /// fadeGain을 target까지 부드럽게 옮긴다. 진행 중인 페이드는 대체된다.
    private func fade(to target: Double, duration: TimeInterval = 0.8, completion: (() -> Void)? = nil) {
        fadeTimer?.invalidate()

        let step = 1.0 / 30.0
        let delta = (target - fadeGain) / (duration / step)
        guard abs(delta) > 0 else { fadeGain = target; applyVolume(); completion?(); return }

        let t = Foundation.Timer(timeInterval: step, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.fadeGain += delta
            let done = delta > 0 ? self.fadeGain >= target : self.fadeGain <= target
            if done {
                self.fadeGain = target
                timer.invalidate()
                self.fadeTimer = nil
            }
            self.applyVolume()
            if done { completion?() }
        }
        RunLoop.main.add(t, forMode: .common)
        fadeTimer = t
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard isPlaying else { return }
        // 곡 사이는 페이드 없이 이어 붙여 끊긴 느낌을 줄인다
        advance(fadeIn: false)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard isPlaying else { return }
        advance(fadeIn: false)
    }
}

// MARK: - Music Bar (타이머 패널 하단)
struct MusicBar: View {
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var library = MusicLibrary.shared

    private var currentTracks: [URL] { library.tracks(for: player.mood) }
    private var isEmpty: Bool { currentTracks.isEmpty }

    var body: some View {
        VStack(spacing: 6) {
            // 분위기 선택 칩
            HStack(spacing: 6) {
                ForEach(MusicMood.allCases) { mood in
                    moodChip(mood)
                }
            }

            HStack(spacing: 10) {
                // 재생/정지
                Button(action: { player.toggle() }) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(isEmpty ? Color.secondary.opacity(0.4) : player.mood.tint)
                }
                .buttonStyle(.plain)
                .disabled(isEmpty)
                .help(player.isPlaying ? "Pause music" : "Play music")

                // 곡명 또는 안내
                Group {
                    if isEmpty {
                        Text("No tracks — add audio to the \(player.mood.label) folder")
                            .foregroundStyle(.tertiary)
                    } else if let title = player.currentTitle, player.isPlaying {
                        Text(title)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(currentTracks.count) track\(currentTracks.count == 1 ? "" : "s") · \(player.mood.label)")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

                // 볼륨
                HStack(spacing: 4) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    Slider(value: $player.volume, in: 0...1)
                        .controlSize(.mini)
                        .frame(width: 56)
                }

                // 더보기
                Menu {
                    Button("Next Track") { player.skip() }
                        .disabled(!player.isPlaying || currentTracks.count < 2)
                    Divider()
                    Toggle("Play With Timer", isOn: $player.followsTimer)
                    Divider()
                    Button("Open \(player.mood.label) Folder") {
                        library.revealInFinder(player.mood)
                    }
                    Button("Refresh") { player.reloadLibrary() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
        .onAppear { library.reload() }
    }

    private func moodChip(_ mood: MusicMood) -> some View {
        let selected = player.mood == mood
        let count = library.tracks(for: mood).count

        return Button(action: { player.mood = mood }) {
            HStack(spacing: 3) {
                Image(systemName: mood.icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(mood.label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(selected ? mood.tint : (count == 0 ? Color.secondary.opacity(0.45) : .secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? mood.tint.opacity(0.14) : Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(selected ? mood.tint.opacity(0.35) : .clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .help(mood.hint + (count == 0 ? " (no tracks)" : " · \(count) track\(count == 1 ? "" : "s")"))
    }
}
