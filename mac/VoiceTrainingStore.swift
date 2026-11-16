import Foundation
import AVFoundation
import CryptoKit

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
    @Published var microphoneProblem: MicrophoneProblem?
    @Published var starting = false
    @Published var recording = false
    @Published var seconds = 0.0
    @Published var frames: [TrainingFrame] = []
    @Published var feedback: TrainingFeedback?
    @Published var rendering = false
    @Published var playing = false
    @Published var exampleContrast = false
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
    var speechRequest: Progress?
    nonisolated static let speechQueue = DispatchQueue(label: "local.shadowstudio.elevenlabs")
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
        speechRequest?.cancel(); speechRequest = nil
        timer?.cancel(); timer = nil
        player?.stop(); player = nil
        playing = false; playingTake = false; rendering = false; playhead = 0
        if let url = exampleURL { try? FileManager.default.removeItem(at: url) }; exampleURL = nil
    }

    func resetTake() {
        stopPlayback()
        if let url = takeURL { try? FileManager.default.removeItem(at: url) }; takeURL = nil
        frames = []; feedback = nil; error = nil; seconds = 0; savedThisTake = false; heardTake = false
        microphoneProblem = nil
    }

    func leave() {
        generation = UUID(); starting = false; recording = false
        recorder?.stop(); recorder = nil
        stopLive(); resetTake()
    }

    func playExample(contrast: Bool = false) async {
        guard !locked else { return }
        if playing || rendering { stopPlayback(); return }
        stopPlayback(); error = nil; rendering = true; exampleContrast = contrast
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
        guard let root = ServerManager.shared.projectDir() else { throw AppError(message: "Shadow Studio couldn't find its folder. Rebuild the Mac app.") }
        let cache = root.appendingPathComponent("data/voice-training-audio", isDirectory: true)
        let request = Progress(totalUnitCount: 1); speechRequest = request
        return try await withCheckedThrowingContinuation { continuation in
            Self.speechQueue.async {
                do {
                    guard !request.isCancelled else { throw CancellationError() }
                    continuation.resume(returning: try Self.elevenLabsSpeech(text, rate: rate, cache: cache))
                }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    nonisolated static func elevenLabsSpeech(_ text: String, rate: Float, cache: URL) throws -> ([Float], Double) {
        let voice = "hpp4J3VqNfWAUOO0d1Us", model = "eleven_multilingual_v2"
        let speed = min(1.2, max(0.7, Double(rate) / 0.45))
        let settings = try JSONSerialization.data(withJSONObject: ["stability": 0.5, "similarity_boost": 0.75, "speed": speed])
        let key = SHA256.hash(data: Data("v1|\(voice)|\(model)|\(speed)|\(text)".utf8)).map { String(format: "%02x", $0) }.joined()
        let target = cache.appendingPathComponent(key + ".pcm")
        let fm = FileManager.default
        if !fm.fileExists(atPath: target.path) {
            guard let executable = ["/opt/homebrew/bin/elevenlabs", "/usr/local/bin/elevenlabs"].first(where: { fm.isExecutableFile(atPath: $0) }) else {
                throw AppError(message: "Install the ElevenLabs CLI with Homebrew, then run elevenlabs auth login in Terminal.")
            }
            try fm.createDirectory(at: cache, withIntermediateDirectories: true)
            let temporary = cache.appendingPathComponent(UUID().uuidString + ".pcm")
            defer { try? fm.removeItem(at: temporary) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["text-to-speech", "convert", "--voice-id", voice, "--model-id", model,
                                 "--text", text, "--voice-settings", String(decoding: settings, as: UTF8.self),
                                 "--output-format", "pcm_22050", "--output", temporary.path, "--no-retry", "--quiet"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            let deadline = Date().addingTimeInterval(90)
            while process.isRunning {
                if Date() > deadline {
                    process.terminate()
                    throw AppError(message: "ElevenLabs took too long. Check your connection before retrying; the request may have used credits.")
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            guard process.terminationStatus == 0 else {
                throw AppError(message: "ElevenLabs couldn't generate this example. Run elevenlabs auth login in Terminal, check your credits and connection, then try again.")
            }
            let size = (try fm.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.intValue ?? 0
            guard size > 0, size <= 22050 * 2 * 60, size % 2 == 0 else {
                throw AppError(message: "ElevenLabs returned an unreadable example. Please try again.")
            }
            try fm.moveItem(at: temporary, to: target)
        }
        let data = try Data(contentsOf: target)
        guard !data.isEmpty, data.count % 2 == 0 else { throw AppError(message: "The saved example couldn't be read. Ask for help restoring the saved audio before regenerating it.") }
        let samples = stride(from: 0, to: data.count, by: 2).map { i -> Float in
            let bits = UInt16(data[i]) | (UInt16(data[i + 1]) << 8)
            return Float(Int16(bitPattern: bits)) / 32768
        }
        return (samples, 22050)
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
        guard !starting, !rendering, !saving, technique != .pace || heardExample else { return }
        starting = true
        defer { starting = false }
        microphoneProblem = nil
        let token = generation
        do { try await MicrophoneProblem.checkInput() }
        catch {
            if generation == token { microphoneProblem = error as? MicrophoneProblem ?? .failed }
            return
        }
        guard generation == token else { return }
        stopPlayback()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shadow-voice-\(UUID().uuidString).wav")
        var newRecorder: AVAudioRecorder?
        do {
            let e = AVAudioEngine(), input = e.inputNode, format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw MicrophoneProblem.unavailable }
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
            let r = try AVAudioRecorder(url: url, settings: settings)
            newRecorder = r
            guard r.record() else { throw MicrophoneProblem.failed }
            let recordingToken = UUID()
            let sr = format.sampleRate, accumulator = SampleBuffer()
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                guard let channel = buffer.floatChannelData?[0] else { return }
                let result = accumulator.add(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)), sr)
                if !result.isEmpty {
                    DispatchQueue.main.async {
                        guard let self, self.generation == recordingToken, self.recording else { return }
                        for frame in result {
                            self.frames.append(TrainingFrame(time: Double(self.frames.count) * 1024 / sr, energy: frame.rms, pitch: frame.hz))
                        }
                    }
                }
            }
            do { try e.start() }
            catch { input.removeTap(onBus: 0); e.stop(); throw error }
            resetTake()
            generation = recordingToken
            takeURL = url; recorder = r; engine = e
            recording = true
            let began = Date()
            timer = Task {
                while !Task.isCancelled {
                    seconds = Date().timeIntervalSince(began)
                    if seconds >= limit { finishRecording(); return }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
        } catch {
            newRecorder?.stop()
            try? FileManager.default.removeItem(at: url)
            microphoneProblem = error as? MicrophoneProblem ?? .failed
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
