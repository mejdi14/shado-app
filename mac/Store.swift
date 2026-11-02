import Foundation
import AVFoundation

enum Mode: String, CaseIterable {
    case listen, recall, shadow
    var title: String { rawValue.capitalized }
    var detail: String { ["listen": "Catch the details", "recall": "Try it on your own", "shadow": "Speak along"][rawValue]! }
    var heading: String { ["listen": "Ready when you are.", "recall": "Hold the phrase. Make it yours.", "shadow": "Follow the speaker’s flow."][rawValue]! }
    var hint: String { ["listen": "Listen first, then record your own take.", "recall": "The words are hidden. Record from memory.", "shadow": "Use headphones. The original plays while you record."][rawValue]! }
}

@MainActor final class Store: NSObject, ObservableObject, AVAudioPlayerDelegate {
    let api: API
    @Published var showLibrary = false
    @Published var library: [LibraryItem] = []
    @Published var lesson: Lesson?
    @Published var index = 0
    @Published var mode = Mode.listen
    @Published var looping = false
    @Published var concealed = false
    @Published var speed = 1.0 { didSet { original?.rate = Float(speed) } }
    @Published var busy: Busy?
    @Published var toast: String?
    @Published var voice: VoiceMap?
    @Published var voiceFailed = false
    @Published var isPlaying = false
    @Published var position = 0.0
    @Published var isTakePlaying = false
    @Published var recording = false
    @Published var starting = false
    @Published var stopping = false
    @Published var recordSeconds = 0.0
    @Published var showImport = false
    @Published var showEdit = false
    @Published var showDelete = false
    @Published var showResplit = false
    @Published var showFeedback = false
    @Published var importUpload = false
    @Published var importURL = ""
    @Published var importFile: URL?
    @Published var importError = ""

    var original: AVAudioPlayer?
    var takePlayer: AVAudioPlayer?
    var recorder: AVAudioRecorder?
    var recordFile: URL?
    var engine: AVAudioEngine?
    var live: LiveTrack?
    var pollTask: Task<Void, Never>?
    var recordTask: Task<Void, Never>?
    var autoStop: Task<Void, Never>?
    var toastTask: Task<Void, Never>?
    var playbackDone: (() -> Void)?
    var playOnce = false

    init(api: API) { self.api = api; super.init() }

    var locked: Bool { recording || starting || stopping || busy != nil }
    var phrase: Phrase? { lesson.flatMap { index < $0.phrases.count ? $0.phrases[index] : nil } }
    var sampleId: String? { library.first { $0.sample }?.id }

    func show(_ message: String) {
        toast = message; toastTask?.cancel()
        toastTask = Task { try? await Task.sleep(nanoseconds: 6_500_000_000); if !Task.isCancelled { toast = nil } }
    }

    func guarded(_ body: () async throws -> Void) async {
        do { try await body() } catch { show(error.localizedDescription) }
    }

    func start() async {
        await guarded {
            try await refreshLibrary()
            if let last = UserDefaults.standard.string(forKey: "shadow-lesson"), library.contains(where: { $0.id == last }) { try await loadLesson(last) }
        }
    }

    func refreshLibrary() async throws { library = try await api.get([LibraryItem].self, "/api/library") }

    func loadLesson(_ id: String, keepIndex: Bool = false) async throws {
        stopPlayback()
        let l = try await api.get(Lesson.self, "/api/lesson/" + id)
        let data = try await api.send("/api/audio/" + id)
        let player = try AVAudioPlayer(data: data)
        player.enableRate = true; player.rate = Float(speed); player.prepareToPlay()
        original = player
        if !keepIndex { index = 0 }
        lesson = l
        index = min(index, l.phrases.count - 1)
        UserDefaults.standard.set(id, forKey: "shadow-lesson")
        phraseChanged()
        try await refreshLibrary()
    }

    func phraseChanged() {
        stopPlayback(); setMode(mode, force: true)
        voice = nil; voiceFailed = false; position = 0
        guard let l = lesson else { return }
        let id = l.id, ix = index
        if live?.key != "\(id):\(ix)" { live = nil }
        Task {
            guard let v = try? await api.get(VoiceData.self, "/api/voice/\(id)/\(ix)") else { if lesson?.id == id, index == ix { voiceFailed = true }; return }
            guard lesson?.id == id, index == ix, let ph = phrase else { return }
            let src = makeTrack(v.source.energy, v.source.pitch) { Double($0 + 1) * v.hop }
            let sp = v.take?.speed ?? 1
            var you: [Pt]? = nil, shift = 0.0, scale = sp
            if let t = v.take {
                let raw = makeTrack(t.energy, t.pitch) { Double($0 + 1) * v.hop * sp }, len = ph.end - ph.start
                shift = onsetX(src) - onsetX(raw)
                if let (a, b) = speechSpan(src), let (c, d) = speechSpan(raw), d > c { scale = (b - a) * sp / (d - c); shift = a - c / sp * scale }
                let sc = scale, sh = shift
                you = raw.map { Pt(x: $0.x / sp * sc + sh, e: $0.e, st: $0.st) }.filter { $0.x >= 0 && $0.x <= len }
                if !recording { live = nil }
            }
            voice = VoiceMap(src: src, pauses: pauses(src), stress: stressed(src, ph.words ?? [], ph.start), you: you, shift: shift, scale: scale, takeSpeed: sp)
        }
    }

    func select(_ i: Int) {
        guard let l = lesson, !locked, i >= 0, i < l.phrases.count else { return }
        index = i; phraseChanged()
    }

    func setMode(_ m: Mode, force: Bool = false) {
        if !force && (recording || starting || stopping) { return }
        mode = m; concealed = m == .recall
    }

    func openLibrary() async { await guarded { try await refreshLibrary(); showLibrary = true } }
    func openLesson(_ id: String) async { await guarded { try await loadLesson(id); showLibrary = false } }

    // MARK: Playback

    func stopPlayback() {
        pollTask?.cancel(); pollTask = nil; playbackDone = nil
        if isPlaying, let p = original, let ph = phrase { position = min(max(0, p.currentTime - ph.start), ph.end - ph.start) }
        original?.pause(); takePlayer?.stop()
        isPlaying = false; isTakePlaying = false
    }

    func playOriginal(once: Bool = false, rate: Double? = nil, excerpt: ClosedRange<Double>? = nil, onDone: (() -> Void)? = nil) {
        guard let p = original, let ph = phrase else { return }
        stopPlayback()
        let from = max(ph.start, min(ph.end, ph.start + (excerpt?.lowerBound ?? 0)))
        let until = min(ph.end, max(from, ph.start + (excerpt?.upperBound ?? (ph.end - ph.start))))
        guard until > from else { return }
        p.rate = Float(rate ?? speed); p.currentTime = from; position = from - ph.start
        playbackDone = onDone; playOnce = once
        p.play(); isPlaying = true
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000)
                guard !Task.isCancelled, let ph = phrase else { return }
                if p.currentTime >= until || !p.isPlaying {
                    if looping && !playOnce && !recording { p.currentTime = from; p.play() }
                    else { let done = playbackDone; stopPlayback(); position = until - ph.start; done?(); return }
                }
            }
        }
    }

    func seek(_ x: Double) {
        guard let ph = phrase else { return }
        position = min(max(0, x), ph.end - ph.start)
        if isPlaying { original?.currentTime = ph.start + position }
    }

    func togglePlay() {
        guard lesson != nil, !starting, !stopping else { return }
        if isPlaying {
            if recording && mode == .shadow { stopRecording(); return }
            stopPlayback()
        } else { playOriginal() }
    }

    func playTake() async {
        guard let r = phrase?.latest else { return }
        stopPlayback()
        await guarded {
            let data = try await api.send(r.audio)
            let p = try AVAudioPlayer(data: data)
            p.delegate = self; takePlayer = p
            p.play(); isTakePlaying = true
        }
    }

    func toggleTake() async {
        if isTakePlaying { stopPlayback() } else { await playTake() }
    }

    func compareAB() {
        playOriginal(once: true, rate: phrase?.latest?.playbackSpeed ?? 1) { [weak self] in Task { await self?.playTake() } }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isTakePlaying = false }
    }

    // MARK: Recording

    func micAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func toggleRecording() async {
        if recording { stopRecording(); return }
        guard lesson != nil, !locked else { return }
        starting = true; stopPlayback()
        guard await micAllowed() else {
            starting = false
            show("Microphone access was denied. Allow Shadow Studio in System Settings → Privacy & Security → Microphone, then try again.")
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        guard let r = try? AVAudioRecorder(url: url, settings: settings), r.record() else {
            starting = false; show("Microphone recording failed. Please try again."); return
        }
        recorder = r; recordFile = url
        recording = true; starting = false; recordSeconds = 0
        startLive()
        let began = Date()
        recordTask = Task { while !Task.isCancelled { recordSeconds = Date().timeIntervalSince(began); try? await Task.sleep(nanoseconds: 200_000_000) } }
        autoStop = Task { try? await Task.sleep(nanoseconds: 34_000_000_000); if !Task.isCancelled { stopRecording() } }
        if mode == .shadow {
            playOriginal(once: true) { [weak self] in
                self?.autoStop?.cancel()
                self?.autoStop = Task { try? await Task.sleep(nanoseconds: 500_000_000); if !Task.isCancelled { self?.stopRecording() } }
            }
        }
    }

    func stopRecording() {
        guard recording, !stopping else { return }
        stopping = true; recording = false
        recordTask?.cancel(); autoStop?.cancel(); stopPlayback(); stopLive()
        recorder?.stop(); recorder = nil
        let url = recordFile
        Task { if let url { await finishRecording(url) }; stopping = false }
    }

    func startLive() {
        guard let l = lesson else { return }
        live = LiveTrack(key: "\(l.id):\(index)", shadow: mode == .shadow, speed: mode == .shadow ? speed : 1)
        let e = AVAudioEngine(), input = e.inputNode, format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { live = nil; return }
        let sr = format.sampleRate, acc = SampleBuffer()
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let ch = buffer.floatChannelData?[0] else { return }
            let results = acc.add(UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)), sr)
            if !results.isEmpty { Task { @MainActor in self?.addLive(results, 1024 / sr) } }
        }
        do { try e.start(); engine = e } catch { input.removeTap(onBus: 0); live = nil }
    }

    func stopLive() { engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil }

    func addLive(_ results: [(rms: Double, hz: Double?)], _ dt: Double) {
        guard recording, var L = live else { return }
        for (k, r) in results.enumerated() {
            if L.shadow {
                if isPlaying, let p = original, let ph = phrase { L.x = p.currentTime - ph.start - Double(results.count - 1 - k) * dt * L.speed }
                else if let x = L.x { L.x = x + dt * L.speed }
            } else if let x = L.x { L.x = x + dt }
            else if r.hz != nil && r.rms > 0.01 { L.x = onsetX(voice?.src ?? []) }
            guard let x = L.x else { continue }
            L.peak = max(L.peak, r.rms); L.frames.append((x, r.rms, r.hz))
        }
        live = L
    }

    func finishRecording(_ url: URL) async {
        guard let l = lesson else { return }
        let ix = index, speedUsed = mode == .shadow ? speed : 1
        defer { try? FileManager.default.removeItem(at: url) }
        await guarded {
            defer { busy = nil }
            busy = Busy(title: "Reviewing your take", message: "Listening to your recording…")
            let j = try await api.get(JobStart.self, "/api/record/\(l.id)/\(ix)?speed=\(speedUsed)", method: "POST", contentType: "audio/wav", file: url)
            _ = try await waitJob(j.jobId, "Reviewing your take")
            try await loadLesson(l.id, keepIndex: true)
            showFeedback = true
            show("Your feedback is ready. Listen back, then choose one detail to practise.")
        }
    }

    // MARK: Jobs, import, edit, delete

    func waitJob(_ id: String, _ title: String) async throws -> String {
        busy = Busy(title: title, message: busy?.message ?? "Preparing audio…")
        while true {
            let j = try await api.get(Job.self, "/api/jobs/" + id)
            busy?.message = j.message ?? "Finishing up…"
            if j.state == "error" { throw AppError(message: j.message ?? "Processing failed. Please try again.") }
            if j.state == "done", let lid = j.lessonId { return lid }
            try await Task.sleep(nanoseconds: 900_000_000)
        }
    }

    func submitImport() async {
        let url = importURL.trimmingCharacters(in: .whitespacesAndNewlines)
        importError = ""
        if importFile == nil && url.isEmpty { importError = "Paste a YouTube link or choose a file."; return }
        if let f = importFile, ((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 150 * 1024 * 1024 { importError = "Choose a file smaller than 150 MB."; return }
        showImport = false
        defer { busy = nil }
        do {
            busy = Busy(title: "Preparing your practice", message: "Preparing audio…")
            let j: JobStart
            if let f = importFile { j = try await uploadFile(f) }
            else { j = try await api.get(JobStart.self, "/api/import", method: "POST", json: ["url": url]) }
            let lid = try await waitJob(j.jobId, "Finding your phrases")
            try await loadLesson(lid); showLibrary = false
            importURL = ""; importFile = nil
            show("Your practice session is ready. Start by listening to the first phrase.")
        } catch { importError = error.localizedDescription; showImport = true }
    }

    func uploadFile(_ file: URL) async throws -> JobStart {
        let access = file.startAccessingSecurityScopedResource()
        defer { if access { file.stopAccessingSecurityScopedResource() } }
        let boundary = "shadow-" + UUID().uuidString
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".multipart")
        defer { try? FileManager.default.removeItem(at: temp) }
        FileManager.default.createFile(atPath: temp.path, contents: nil)
        let out = try FileHandle(forWritingTo: temp)
        out.write(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(file.lastPathComponent.replacingOccurrences(of: "\"", with: ""))\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        let input = try FileHandle(forReadingFrom: file)
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty { out.write(chunk) }
        try input.close()
        out.write(Data("\r\n--\(boundary)--\r\n".utf8)); try out.close()
        return try await api.get(JobStart.self, "/api/upload", method: "POST", contentType: "multipart/form-data; boundary=\(boundary)", file: temp)
    }

    func savePhrase(text: String, start: Double, end: Double) async -> String? {
        guard let l = lesson else { return nil }
        do {
            lesson = try await api.get(Lesson.self, "/api/phrase/\(l.id)/\(index)", method: "PATCH", json: ["text": text, "start": start, "end": end])
            phraseChanged()
            show("Phrase updated. Record a new take to compare with this version.")
            return nil
        } catch { return error.localizedDescription }
    }

    func resplitLesson() async {
        guard let l = lesson else { return }
        await guarded {
            defer { busy = nil }
            stopPlayback()
            busy = Busy(title: "Finding new phrases", message: "Preparing audio…")
            let j = try await api.get(JobStart.self, "/api/resplit/" + l.id, method: "POST")
            _ = try await waitJob(j.jobId, "Finding new phrases")
            try await loadLesson(l.id)
            show("New phrases are ready. Start again from the first phrase.")
        }
    }

    func deleteLesson() async {
        guard let l = lesson else { return }
        await guarded {
            _ = try await api.send("/api/lesson/" + l.id, method: "DELETE")
            stopPlayback(); lesson = nil; original = nil; voice = nil; live = nil
            UserDefaults.standard.removeObject(forKey: "shadow-lesson")
            try await refreshLibrary()
        }
    }
}
