import Foundation
import AVFoundation

struct TrainingFrame { let time: Double; let energy: Double; let pitch: Double? }
struct TrainingFeedback { let title: String; let detail: String; let good: Bool; let usable: Bool }

func trainingSpans(_ exercise: VoiceExercise, _ technique: VoiceTechnique) -> [(Double, Double)] {
    let weights = exercise.units.indices.map { i -> Double in
        if technique == .rhythm { return exercise.strong.contains(i) ? 1.4 : 0.65 }
        return Double(max(2, exercise.units[i].count)) * (exercise.strong.contains(i) ? 1.25 : 1)
    }
    let total = max(1, weights.reduce(0, +))
    var x = 0.0
    return weights.map { w in let a = x; x += w / total; return (a, x) }
}

func trainingEnvelope(_ exercise: VoiceExercise, _ technique: VoiceTechnique, _ fraction: Double, strong: [Int]? = nil) -> Double {
    if !exercise.units.isEmpty && (technique == .rhythm || technique == .stress || technique == .energy) {
        let spans = trainingSpans(exercise, technique)
        let i = spans.firstIndex { fraction <= $0.1 } ?? (spans.count - 1)
        let (a, b) = spans[i], phase = min(1, max(0, (fraction - a) / max(0.001, b - a)))
        return ((strong ?? exercise.strong).contains(i) ? 0.95 : 0.32) * pow(max(0, sin(.pi * phase)), 0.5)
    }
    return 0.25 + (exercise.pattern.value(fraction) + 3) / 6 * 0.65
}

@MainActor final class VoiceTrainingStore: NSObject, ObservableObject, AVAudioPlayerDelegate {
    let api: API
    @Published var technique = VoiceTechnique.pitch
    @Published var level = 0
    @Published var completed = Set<String>()
    @Published var loadingProgress = false
    @Published var progressError: String?
    @Published var error: String?
    @Published var starting = false
    @Published var recording = false
    @Published var seconds = 0.0
    @Published var frames: [TrainingFrame] = []
    @Published var feedback: TrainingFeedback?
    @Published var rendering = false
    @Published var playing = false
    @Published var playingTake = false
    @Published var playhead = 0.0
    @Published var saving = false
    @Published var savedThisTake = false
    @Published var heardExample = false
    @Published var heardTake = false
    @Published var targetDuration: Double = 3

    var exercise: VoiceExercise { technique.exercises[level] }
    var locked: Bool { starting || recording }
    var limit: Double { min(14, max(6, targetDuration * 2 + 2)) }
    var takeURL: URL?
    var exampleURL: URL?
    var recorder: AVAudioRecorder?
    var engine: AVAudioEngine?
    var player: AVAudioPlayer?
    var timer: Task<Void, Never>?
    var generation = UUID()
    var speech = AVSpeechSynthesizer()
    var speechSamples: [Float] = []
    var speechRate = 22050.0
    var speechContinuation: CheckedContinuation<([Float], Double), Error>?
    var speechTimeout: Task<Void, Never>?
    var rememberedLevels: [VoiceTechnique: Int] = [:]

    init(api: API) { self.api = api; super.init() }
    func count(_ technique: VoiceTechnique) -> Int { technique.exercises.filter { completed.contains($0.key(technique)) }.count }
    func isCompleted(_ exercise: VoiceExercise) -> Bool { completed.contains(exercise.key(technique)) }

    func loadProgress() async {
        guard !loadingProgress else { return }
        loadingProgress = true; progressError = nil
        defer { loadingProgress = false }
        do { completed.formUnion(try await api.get(TrainingProgress.self, "/api/voice-training/progress").completed) }
        catch { progressError = error.localizedDescription }
    }

    func markPracticed() async {
        guard !saving, !locked, feedback?.usable == true, !savedThisTake else { return }
        if technique.selfReview && !heardTake { return }
        await saveProgress(exercise.key(technique))
    }

    func saveProgress(_ key: String) async {
        guard !saving else { return }
        saving = true; progressError = nil
        defer { saving = false }
        do {
            let progress = try await api.get(TrainingProgress.self, "/api/voice-training/progress", method: "POST", json: ["exercise": key])
            completed.formUnion(progress.completed)
            if exercise.key(technique) == key { savedThisTake = true }
        } catch { progressError = error.localizedDescription }
    }

    func select(_ technique: VoiceTechnique, level: Int? = nil) {
        guard !locked, !saving else { return }
        rememberedLevels[self.technique] = self.level
        resetTake(); heardExample = false
        self.technique = technique
        self.level = min(technique.exercises.count - 1, max(0, level ?? rememberedLevels[technique] ?? 0))
        targetDuration = exercise.duration
    }

    func stopPlayback() {
        generation = UUID()
        timer?.cancel(); timer = nil
        player?.stop(); player = nil
        speech.stopSpeaking(at: .immediate)
        speechTimeout?.cancel(); speechTimeout = nil
        let continuation = speechContinuation; speechContinuation = nil
        continuation?.resume(throwing: CancellationError())
        playing = false; playingTake = false; rendering = false; playhead = 0
        if let url = exampleURL { try? FileManager.default.removeItem(at: url) }; exampleURL = nil
    }

    func resetTake() {
        stopPlayback()
        if let url = takeURL { try? FileManager.default.removeItem(at: url) }; takeURL = nil
        frames = []; feedback = nil; error = nil; seconds = 0; savedThisTake = false; heardTake = false
    }

    func leave() {
        generation = UUID(); starting = false; recording = false
        recorder?.stop(); recorder = nil
        stopLive(); resetTake()
    }

    func playExample(contrast: Bool = false) async {
        guard !locked else { return }
        if playing || rendering { stopPlayback(); return }
        stopPlayback(); error = nil; rendering = true
        let token = generation, ex = exercise, skill = technique
        do {
            let samples: [Float], sr: Double
            if ex.isTone {
                sr = 22050
                samples = makeTone(ex, skill, contrast ? ex.contrastPattern : ex.pattern, sr)
            } else {
                (samples, sr) = try await renderSpeech(contrast ? (ex.contrast ?? ex.spoken!) : ex.spoken!, rate: contrast && skill.selfReview ? 0.32 : ex.rate)
            }
            guard generation == token else { return }
            var sound = samples
            if !ex.isTone {
                let peak = sound.reduce(Float(0)) { max($0, abs($1)) }, gate = max(0.002, peak * 0.03)
                if let a = sound.firstIndex(where: { abs($0) > gate }), let b = sound.lastIndex(where: { abs($0) > gate }) {
                    let padding = Int(sr * 0.02)
                    sound = Array(sound[max(0, a - padding)...min(sound.count - 1, b + padding)])
                }
            }
            if skill == .stress || (skill == .energy && !ex.units.isEmpty) {
                let strong = contrast ? ex.contrastStrong : ex.strong
                for i in sound.indices {
                    let gain = 0.22 + 0.78 * trainingEnvelope(ex, skill, Double(i) / Double(max(1, sound.count - 1)), strong: strong)
                    sound[i] *= Float(gain)
                }
            }
            let url = try writeAudio(sound, sr)
            exampleURL = url
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self; p.enableRate = true
            // Only pace drills fit a fixed duration. Other speech examples keep their natural timing.
            if skill == .pace { p.rate = Float(min(2, max(0.5, p.duration / ex.duration))) }
            if !contrast { targetDuration = p.duration / Double(p.rate); heardExample = true }
            guard p.play() else { throw AppError(message: "The example couldn’t play. Try again or check your sound output.") }
            player = p; rendering = false; playing = true
            startPlaybackTimer(duration: p.duration)
        } catch is CancellationError { }
        catch { if generation == token { rendering = false; stopPlayback(); self.error = error.localizedDescription } }
    }

    func playTake() {
        guard !locked, let url = takeURL else { return }
        if playingTake { stopPlayback(); return }
        stopPlayback(); error = nil
        do {
            let p = try AVAudioPlayer(contentsOf: url); p.delegate = self
            guard p.play() else { throw AppError(message: "Your take couldn’t play. Try recording again.") }
            player = p; playingTake = true; heardTake = true; startPlaybackTimer(duration: p.duration)
        } catch { self.error = error.localizedDescription }
    }

    func startPlaybackTimer(duration: Double) {
        timer = Task {
            while !Task.isCancelled {
                guard let player else { return }
                playhead = player.currentTime / max(0.01, duration)
                try? await Task.sleep(nanoseconds: 30_000_000)
                if !player.isPlaying { playing = false; playingTake = false; playhead = 0; return }
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.playing = false; self.playingTake = false; self.playhead = 0; self.timer?.cancel()
        }
    }

    func renderSpeech(_ text: String, rate: Float) async throws -> ([Float], Double) {
        guard let voice = AVSpeechSynthesisVoice(language: "en-US") else { throw AppError(message: "An English Mac voice is needed. Add one in System Settings → Accessibility → Spoken Content.") }
        speechSamples = []; speech = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text); utterance.voice = voice; utterance.rate = rate
        let token = generation
        return try await withCheckedThrowingContinuation { continuation in
            speechContinuation = continuation
            speechTimeout = Task {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled, generation == token, let pending = speechContinuation else { return }
                speechContinuation = nil; speech.stopSpeaking(at: .immediate)
                pending.resume(throwing: AppError(message: "The Mac voice didn’t produce an example. Check your installed English voices and try again."))
            }
            speech.write(utterance) { [weak self] buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                let done = pcm.frameLength == 0, sr = pcm.format.sampleRate
                let copy: [Float]
                if let channel = pcm.floatChannelData?[0] { copy = Array(UnsafeBufferPointer(start: channel, count: Int(pcm.frameLength))) }
                else if let channel = pcm.int16ChannelData?[0] { copy = UnsafeBufferPointer(start: channel, count: Int(pcm.frameLength)).map { Float($0) / 32768 } }
                else { copy = [] }
                DispatchQueue.main.async {
                    guard let self, self.generation == token, self.speechContinuation != nil else { return }
                    if !copy.isEmpty { self.speechSamples.append(contentsOf: copy); self.speechRate = sr }
                    if done {
                        self.speechTimeout?.cancel()
                        let pending = self.speechContinuation; self.speechContinuation = nil
                        if self.speechSamples.isEmpty { pending?.resume(throwing: AppError(message: "The Mac voice returned no audio. Choose an installed English voice and try again.")) }
                        else { pending?.resume(returning: (self.speechSamples, self.speechRate)) }
                    }
                }
            }
        }
    }

    func makeTone(_ ex: VoiceExercise, _ skill: VoiceTechnique, _ pattern: VoicePattern, _ sr: Double) -> [Float] {
        var phase = 0.0
        var sound: [Float] = []
        sound.reserveCapacity(Int(sr * ex.duration))
        for i in 0..<Int(sr * ex.duration) {
            let t = Double(i) / sr, f = t / ex.duration
            let hz = 180 * pow(2, (skill == .pitch ? pattern.value(f) : 0) / 12)
            phase += 2 * .pi * hz / sr
            let edge = min(1, min(t / 0.04, (ex.duration - t) / 0.04))
            let envelope = skill == .energy ? 0.25 + (pattern.value(f) + 3) / 6 * 0.65 : skill == .rhythm ? trainingEnvelope(ex, skill, f) : 0.65
            let harmonic = sin(phase) + 0.3 * sin(2 * phase) + 0.12 * sin(3 * phase)
            sound.append(Float(harmonic * 0.23 * envelope * edge))
        }
        return sound
    }

    func writeAudio(_ samples: [Float], _ sr: Double) throws -> URL {
        guard !samples.isEmpty, let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { throw AppError(message: "The example audio couldn’t be prepared.") }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shadow-voice-\(UUID().uuidString).caf")
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        catch { try? FileManager.default.removeItem(at: url); throw error }
        return url
    }

    func toggleRecording() async {
        if recording { finishRecording(); return }
        guard !starting, !rendering else { return }
        resetTake(); starting = true
        let token = generation
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .audio)
        default: allowed = false
        }
        guard generation == token else { return }
        guard allowed else { starting = false; error = "Allow Shadow Studio in System Settings → Privacy & Security → Microphone, then try again."; return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shadow-voice-\(UUID().uuidString).wav")
        takeURL = url
        do {
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
            let r = try AVAudioRecorder(url: url, settings: settings)
            guard r.record() else { throw AppError(message: "The microphone couldn’t start. Check your input device and try again.") }
            recorder = r
            let e = AVAudioEngine(), input = e.inputNode, format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw AppError(message: "No microphone input is available. Select a microphone in System Settings → Sound.") }
            let sr = format.sampleRate, accumulator = SampleBuffer()
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                guard let channel = buffer.floatChannelData?[0] else { return }
                let result = accumulator.add(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)), sr)
                if !result.isEmpty {
                    DispatchQueue.main.async {
                        guard let self, self.generation == token, self.recording else { return }
                        for frame in result {
                            self.frames.append(TrainingFrame(time: Double(self.frames.count) * 1024 / sr, energy: frame.rms, pitch: frame.hz))
                        }
                    }
                }
            }
            engine = e; try e.start()
            recording = true; starting = false
            let began = Date()
            timer = Task {
                while !Task.isCancelled {
                    seconds = Date().timeIntervalSince(began)
                    if seconds >= limit { finishRecording(); return }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
        } catch {
            recorder?.stop(); recorder = nil; stopLive(); starting = false
            if let url = takeURL { try? FileManager.default.removeItem(at: url) }; takeURL = nil
            self.error = error.localizedDescription
        }
    }

    func stopLive() { engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil }

    func finishRecording() {
        guard recording else { return }
        recording = false; generation = UUID(); timer?.cancel(); timer = nil
        recorder?.stop(); recorder = nil; stopLive()
        feedback = analyze()
        if feedback?.good == true {
            let key = exercise.key(technique)
            Task { await saveProgress(key) }
        }
    }

    var activeFrames: [TrainingFrame] {
        let peak = frames.map(\.energy).max() ?? 0, gate = max(0.008, peak * 0.1)
        guard let a = frames.firstIndex(where: { $0.energy > gate }), let b = frames.lastIndex(where: { $0.energy > gate }) else { return [] }
        return Array(frames[a...b])
    }
    var takeDuration: Double { guard let a = activeFrames.first, let b = activeFrames.last else { return 0 }; return b.time - a.time + 0.04 }
    var pitchCurve: [Double?] {
        let valid = activeFrames.compactMap(\.pitch).sorted()
        guard !valid.isEmpty else { return [] }
        let median = valid[valid.count / 2]
        return smoothPitch(activeFrames.map { $0.pitch.map { 12 * log2($0 / median) } })
    }
    var energyCurve: [Double] {
        let values = activeFrames.map(\.energy), peak = values.max() ?? 0
        return values.indices.map { i in
            let range = max(0, i - 2)...min(values.count - 1, i + 2)
            return range.map { values[$0] }.reduce(0, +) / Double(range.count) / max(peak, 0.001)
        }
    }
    var pausePositions: [(Double, Double)] {
        let values = energyCurve
        guard !values.isEmpty else { return [] }
        let dt = takeDuration / Double(values.count)
        var result: [(Double, Double)] = [], start: Int?
        for i in values.indices {
            if values[i] < 0.12 && start == nil { start = i }
            if values[i] >= 0.12, let s = start {
                if Double(i - s) * dt >= 0.18 { result.append((Double(s) / Double(values.count), Double(i) / Double(values.count))) }
                start = nil
            }
        }
        return result
    }

    func analyze() -> TrainingFeedback {
        let ex = exercise, active = activeFrames
        guard active.count >= 12, takeDuration >= 0.45 else { return TrainingFeedback(title: "Let’s try a clearer take", detail: "We didn’t catch enough clear sound. Check your microphone and try the whole exercise again.", good: false, usable: false) }
        if ex.isTone && takeDuration < targetDuration * 0.6 {
            return TrainingFeedback(title: "Keep the sound going a little longer.", detail: "Try the full pattern from start to finish. Stay relaxed and use another breath if you need one.", good: false, usable: true)
        }
        if technique.selfReview { return TrainingFeedback(title: "Listen for one small detail", detail: ex.review, good: false, usable: true) }
        if technique.usesPitch {
            let curve = pitchCurve, voiced = curve.compactMap { $0 }
            guard voiced.count >= 12, voiced.count > curve.count / 5 else { return TrainingFeedback(title: "The pitch line needs a clearer voice", detail: "Try a gentle, voiced sound near the microphone. Avoid whispering; keep the note comfortable.", good: false, usable: false) }
            let spread = sqrt(voiced.map { $0 * $0 }.reduce(0, +) / Double(voiced.count))
            if ex.pattern == .flat {
                let good = spread < 1.2
                return TrainingFeedback(title: good ? "A steady note." : "Your note moved a little.", detail: good ? "You held a comfortable pitch. Try it again with the same relaxed voice." : "Aim for one easy note and keep the line level.", good: good, usable: true)
            }
            guard spread > 0.6 else { return TrainingFeedback(title: "Your pitch stayed quite flat.", detail: "Make the rise or fall a little more noticeable, within your comfortable range.", good: false, usable: true) }
            // Keep time positions when comparing shapes; unvoiced gaps don't become adjacent notes.
            let points = curve.indices.compactMap { i -> (Double, Double)? in curve[i].map { (Double(i) / Double(max(1, curve.count - 1)), $0) } }
            let actual = points.map(\.1), target = points.map { ex.pattern.value($0.0) }
            let similarity = correlation(actual, target), good = similarity > 0.6
            let title = good ? (ex.pattern == .rise ? "Good rise." : ex.pattern == .fall ? "Good fall." : "You followed the movement.") : "Try the shape once more."
            return TrainingFeedback(title: title, detail: good ? "Your voice followed the requested shape in your own pitch range." : "Listen again, then follow the direction of the target line. Keep the movement gentle.", good: good, usable: true)
        }
        if technique == .pace {
            let ratio = takeDuration / targetDuration, good = (0.85...1.15).contains(ratio)
            return TrainingFeedback(title: good ? "Your overall pace is close." : ratio > 1 ? "A little slower than the target." : "A little faster than the target.", detail: good ? "Replay to check that both halves feel equally steady." : ratio > 1 ? "Keep the phrase moving. Try leaving a little less space between words." : "Give the words a little more time, without adding extra pauses.", good: good, usable: true)
        }
        if technique == .pauses {
            let detected = pausePositions.map { ($0.0 + $0.1) / 2 }
            let differences = zip(detected, ex.pauseAt).map { pair in pair.0 - pair.1 }
            let good = detected.count == ex.pauseAt.count && differences.allSatisfy { abs($0) < 0.16 }
            let early = (differences.first { abs($0) >= 0.16 } ?? 0) < 0
            let title = good ? "Your phrase groups are taking shape." : detected.count > ex.pauseAt.count ? "Try keeping each group together." : detected.count < ex.pauseAt.count ? "Leave a little space between groups." : early ? "Your pause came a little early." : "Your pause came a little late."
            return TrainingFeedback(title: title, detail: good ? "The estimated gaps are near the target dividers. Replay to hear whether the groups feel natural." : "Follow the dividers and keep the words inside each group flowing. The pause markers are estimates.", good: good, usable: true)
        }
        let energy = energyCurve
        if technique == .stress || (technique == .energy && !ex.units.isEmpty) {
            let spans = trainingSpans(ex, technique)
            let means = spans.map { a, b -> Double in
                let slice = energy.indices.filter { Double($0) / Double(energy.count) >= a && Double($0) / Double(energy.count) < b }.map { energy[$0] }
                return slice.reduce(0, +) / Double(max(1, slice.count))
            }
            let loudest = means.indices.max { means[$0] < means[$1] } ?? 0
            let rest = means.indices.filter { !ex.strong.contains($0) }.map { means[$0] }
            let base = rest.reduce(0, +) / Double(max(1, rest.count))
            let good = ex.strong.contains(loudest) && (means.max() ?? 0) > base * 1.18
            return TrainingFeedback(title: good ? "The emphasis is coming through." : "Give the highlighted part more strength.", detail: "This compares energy in approximate time groups, not recognized syllables. Replay to check where you hear the emphasis.", good: good, usable: true)
        }
        let target = energy.indices.map { trainingEnvelope(ex, technique, Double($0) / Double(max(1, energy.count - 1))) }
        if technique == .energy && ex.pattern == .flat {
            let mean = energy.reduce(0, +) / Double(energy.count)
            let variation = sqrt(energy.map { pow($0 - mean, 2) }.reduce(0, +) / Double(energy.count))
            let good = variation < 0.18
            return TrainingFeedback(title: good ? "Your energy stayed steady." : "Try keeping the same energy.", detail: "Use a comfortable, relaxed sound. There’s no need to get louder.", good: good, usable: true)
        }
        let good = correlation(energy, target) > 0.55
        return TrainingFeedback(title: good ? (technique == .rhythm ? "The strong and soft beats are taking shape." : "Good change in energy.") : (technique == .rhythm ? "Make the strong beats stand out." : "Try the energy movement again."), detail: technique == .rhythm ? "The energy trace is a rough timing guide. Listen back for lighter, shorter syllables between the beats." : "Follow the target from softer to stronger, or back again. Stay within an easy volume.", good: good, usable: true)
    }

    func correlation(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, a.count > 2 else { return 0 }
        let ma = a.reduce(0, +) / Double(a.count), mb = b.reduce(0, +) / Double(b.count)
        let aa = a.map { $0 - ma }, bb = b.map { $0 - mb }
        let denominator = sqrt(aa.map { $0 * $0 }.reduce(0, +) * bb.map { $0 * $0 }.reduce(0, +))
        return zip(aa, bb).map { pair in pair.0 * pair.1 }.reduce(0, +) / max(0.000001, denominator)
    }
}
