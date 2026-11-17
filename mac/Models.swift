import Foundation

struct Mark: Codable { let word: String; let match: Bool }
struct Curves: Codable { let original: [Double]; let you: [Double] }
struct PhraseRevision: Codable { let id: String; let start: Double; let end: Double; let text: String }
struct TakeResult: Codable, Identifiable {
    let id: String; let audio: String; let accuracy: Int; let rhythm: Int; let intonation: Int?
    let words: [Mark]; let curves: Curves; let tips: [String]; let playbackSpeed: Double?; let durationRatio: Double?
    let created: Double?; let phraseRevision: PhraseRevision?; let legacy: Bool?; let recordedSeconds: Double?
}
struct Word: Codable { let start: Double; let end: Double; let word: String }
struct Phrase: Codable { var start: Double; var end: Double; var text: String; var words: [Word]?; var practised: Bool?; var latest: TakeResult?; var takes: Int?; var revision: String? }
struct Lesson: Codable { let id: String; var title: String; let source: String; let duration: Double; var phrases: [Phrase]; let sample: Bool?; let language: String?; let takeHistory: [TakeResult]? }
struct LibraryItem: Codable, Identifiable {
    let id: String; let title: String; let source: String; let duration: Double; let sample: Bool; let count: Int; let practised: Int; let language: String?
    let lastPractised: Double?; let recordedSeconds: Double?; let timedTakes: Int?; let savedTakes: Int?
}
struct EngineStatus: Decodable {
    let local: Bool
    let modelReady: Bool?
    let ffmpeg: Bool?
    let elevenLabsCLI: Bool?
}
struct JobStart: Codable { let jobId: String; let takeId: String? }
struct TakeSubmission: Decodable { let jobId: String?; let takeId: String }
struct Job: Codable { let state: String; let message: String?; let lessonId: String? }
struct PDFVoice: Codable, Identifiable { let id: String; let name: String; let about: String; let gender: String; let accent: String }
struct Busy { var title: String; var message: String }
struct Track: Codable { let energy: [Double]; let pitch: [Double?]; let speed: Double? }
struct VoiceData: Codable { let hop: Double; let source: Track; let take: Track? }
struct TrainingProgress: Codable { var completed: [String] }
struct BackupRestoreResult: Decodable {
    let restoredLessons: Int
    let skippedLessons: Int
    let skippedSample: Int
    let trainingAdded: Int

    var summary: String {
        var result = ["Sessions restored: \(restoredLessons)."]
        if skippedLessons > 0 { result.append("Existing session IDs skipped: \(skippedLessons).") }
        if skippedSample > 0 { result.append("Your existing guided sample was kept.") }
        if trainingAdded > 0 { result.append("Voice Training completions added: \(trainingAdded).") }
        return result.joined(separator: " ")
    }
}

func fmt(_ n: Double) -> String { String(format: "%02d:%02d", Int(n) / 60, Int(n) % 60) }

// MARK: Voice map analysis (relative pitch in semitones, loudness 0–1, x in phrase seconds)

struct Pt { let x: Double; let e: Double; var st: Double? }
struct VoiceMap { let src: [Pt]; let pauses: [(Double, Double)]; let stress: Set<Int>; let you: [Pt]?; let shift: Double; let scale: Double; let takeSpeed: Double }
struct LiveTrack {
    let key: String; let shadow: Bool; let speed: Double
    var x: Double? = nil; var peak = 0.02; var frames: [(x: Double, rms: Double, hz: Double?)] = []
    var track: [Pt] { makeTrack(frames.map { $0.rms / peak }, frames.map(\.hz)) { frames[$0].x } }
}
let activeLevel = 0.1

func makeTrack(_ e: [Double], _ hz: [Double?], _ x: (Int) -> Double) -> [Pt] {
    let v = hz.compactMap { $0 }.sorted(), med = v.isEmpty ? nil : v[v.count / 2]
    let st = smoothPitch(e.indices.map { i -> Double? in
        guard i < hz.count, let h = hz[i], let m = med else { return nil }
        let s = 12 * log2(h / m), f = s > 8 ? s - 12 : s < -8 ? s + 12 : s
        return abs(f) > 12 ? nil : f
    })
    return e.indices.map { Pt(x: x($0), e: e[$0], st: st[$0]) }
}

func smoothPitch(_ v: [Double?]) -> [Double?] {
    var out = v, i = 0
    while i < v.count {
        guard v[i] != nil else { i += 1; continue }
        var j = i
        while j < v.count, v[j] != nil { j += 1 }
        let m = (i..<j).map { k in (max(i, k - 2)...min(j - 1, k + 2)).compactMap { v[$0] }.sorted()[(min(j - 1, k + 2) - max(i, k - 2) + 1) / 2] }
        for k in i..<j { out[k] = j - i < 4 ? nil : (m[max(0, k - i - 1)] + m[k - i] + m[min(j - i - 1, k - i + 1)]) / 3 }
        i = j
    }
    return out
}

func onsetIndex(_ e: [Double]) -> Int { e.firstIndex { $0 > activeLevel } ?? 0 }
func onsetX(_ t: [Pt]) -> Double { t.isEmpty ? 0 : t[onsetIndex(t.map(\.e))].x }
func speechSpan(_ t: [Pt]) -> (Double, Double)? {
    guard let a = t.firstIndex(where: { $0.e > activeLevel }), let b = t.lastIndex(where: { $0.e > activeLevel }) else { return nil }
    return (t[a].x, t[b].x)
}

func pauses(_ t: [Pt]) -> [(Double, Double)] {
    guard let a = t.firstIndex(where: { $0.e > activeLevel }), let b = t.lastIndex(where: { $0.e > activeLevel }) else { return [] }
    var out: [(Double, Double)] = [], s: Int? = nil
    for i in a...b {
        let on = t[i].e > activeLevel
        if !on && s == nil { s = i }
        if on, let st = s { if t[i].x - t[st].x >= 0.149 { out.append((t[st].x, t[i].x)) }; s = nil }
    }
    return out
}

func ending(_ t: [Pt]) -> String {
    let v = t.compactMap(\.st)
    guard v.count >= 12 else { return "" }
    let m = { (a: ArraySlice<Double>) in a.reduce(0, +) / Double(a.count) }
    let d = m(v.suffix(5)) - m(v.dropLast(5).suffix(10))
    return d > 1.2 ? "goes up ↗" : d < -1.2 ? "goes down ↘" : "stays flat →"
}

func stressed(_ t: [Pt], _ words: [Word], _ start: Double) -> Set<Int> {
    guard !t.isEmpty, !words.isEmpty else { return [] }
    let peaks = words.map { w in t.filter { $0.x >= w.start - start && $0.x <= w.end - start }.map(\.e).max() ?? 0 }
    let cut = max(0.5, peaks.sorted(by: >)[max(0, Int((Double(words.count) / 4).rounded()) - 1)])
    return Set(peaks.indices.filter { peaks[$0] >= cut })
}

func detectPitch(_ b: ArraySlice<Float>, _ sr: Double) -> (rms: Double, hz: Double?) {
    let n = b.count / 2, s = sr / 2, o = b.startIndex
    var x = [Float](repeating: 0, count: n), m: Float = 0, e: Float = 0
    for i in 0..<n { x[i] = (b[o + 2 * i] + b[o + 2 * i + 1]) / 2; m += x[i] }
    m /= Float(n)
    for i in 0..<n { x[i] -= m; e += x[i] * x[i] }
    let rms = Double((e / Float(n)).squareRoot())
    if rms < 0.006 { return (rms, nil) }
    let lo = Int(s / 400), hi = min(n / 2, Int((s / 60).rounded(.up)))
    guard lo > 0, hi > lo + 1 else { return (rms, nil) }
    var c = [Float](repeating: 0, count: hi + 2), best: Float = 0
    for l in lo...hi { var sum: Float = 0; for i in 0..<(n - l) { sum += x[i] * x[i + l] }; c[l] = sum / Float(n - l); best = max(best, c[l]) }
    if best / (e / Float(n)) < 0.45 { return (rms, nil) }
    for l in (lo + 1)..<hi where c[l] >= 0.9 * best && c[l] >= c[l - 1] && c[l] >= c[l + 1] { return (rms, s / Double(l)) }
    return (rms, nil)
}

final class SampleBuffer {
    var data: [Float] = []
    func add(_ p: UnsafeBufferPointer<Float>, _ sr: Double) -> [(rms: Double, hz: Double?)] {
        data.append(contentsOf: p)
        var out: [(rms: Double, hz: Double?)] = []
        while data.count >= 2048 { out.append(detectPitch(data[0..<2048], sr)); data.removeFirst(1024) }
        return out
    }
}
