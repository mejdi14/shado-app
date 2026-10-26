import Foundation

struct Mark: Codable { let word: String; let match: Bool }
struct Curves: Codable { let original: [Double]; let you: [Double] }
struct TakeResult: Codable {
    let id: String; let audio: String; let accuracy: Int; let rhythm: Int; let intonation: Int?
    let words: [Mark]; let curves: Curves; let tips: [String]; let playbackSpeed: Double?
}
struct Word: Codable { let start: Double; let end: Double; let word: String }
struct Phrase: Codable { var start: Double; var end: Double; var text: String; var words: [Word]?; var practised: Bool?; var latest: TakeResult?; var takes: Int? }
struct Lesson: Codable { let id: String; var title: String; let source: String; let duration: Double; var phrases: [Phrase]; let sample: Bool? }
struct LibraryItem: Codable, Identifiable { let id: String; let title: String; let source: String; let duration: Double; let sample: Bool; let count: Int; let practised: Int }
struct JobStart: Codable { let jobId: String }
struct Job: Codable { let state: String; let message: String?; let lessonId: String? }
struct Busy { var title: String; var message: String }
struct Track: Codable { let energy: [Double]; let pitch: [Double?]; let speed: Double? }
struct VoiceData: Codable { let hop: Double; let source: Track; let take: Track? }

func fmt(_ n: Double) -> String { String(format: "%02d:%02d", Int(n) / 60, Int(n) % 60) }

// MARK: Voice map analysis (relative pitch in semitones, loudness 0–1, x in phrase seconds)

struct Pt { let x: Double; let e: Double; var st: Double? }
struct VoiceMap { let src: [Pt]; let pauses: [(Double, Double)]; let stress: Set<Int>; let you: [Pt]?; let shift: Double; let takeSpeed: Double }
struct LiveTrack {
    let key: String; let shadow: Bool; let speed: Double
    var x: Double? = nil; var peak = 0.02; var frames: [(x: Double, rms: Double, hz: Double?)] = []
    var track: [Pt] { makeTrack(frames.map { $0.rms / peak }, frames.map(\.hz)) { frames[$0].x } }
}
let activeLevel = 0.1

func makeTrack(_ e: [Double], _ hz: [Double?], _ x: (Int) -> Double) -> [Pt] {
    let v = hz.compactMap { $0 }.sorted(), med = v.isEmpty ? nil : v[v.count / 2]
    var t = e.indices.map { i in Pt(x: x(i), e: e[i], st: i < hz.count ? hz[i].flatMap { h in med.map { 12 * log2(h / $0) } } : nil) }
    let raw = t.map(\.st)
    for i in t.indices {
        guard let s = raw[i] else { continue }
        if abs(s) > 12 { t[i].st = nil }
        else if i > 0, i < t.count - 1, let a = raw[i - 1], let b = raw[i + 1], abs(s - a) > 5, abs(s - b) > 5 { t[i].st = nil }
    }
    return t
}

func onsetIndex(_ e: [Double]) -> Int { e.firstIndex { $0 > activeLevel } ?? 0 }
func onsetX(_ t: [Pt]) -> Double { t.isEmpty ? 0 : t[onsetIndex(t.map(\.e))].x }

func pauses(_ t: [Pt]) -> [(Double, Double)] {
    guard let a = t.firstIndex(where: { $0.e > activeLevel }), let b = t.lastIndex(where: { $0.e > activeLevel }) else { return [] }
    var out: [(Double, Double)] = [], s: Int? = nil
    for i in a...b {
        let on = t[i].e > activeLevel
        if !on && s == nil { s = i }
        if on, let st = s { if t[i].x - t[st].x >= 0.2 { out.append((t[st].x, t[i].x)) }; s = nil }
    }
    return out
}

func ending(_ t: [Pt]) -> String {
    let v = t.compactMap(\.st)
    guard v.count >= 12 else { return "" }
    let m = { (a: ArraySlice<Double>) in a.reduce(0, +) / Double(a.count) }
    let d = m(v.suffix(5)) - m(v.dropLast(5).suffix(10))
    return d > 1.2 ? "rising ↗" : d < -1.2 ? "falling ↘" : "level →"
}

func describe(_ t: [Pt]) -> String {
    guard let a = t.firstIndex(where: { $0.e > activeLevel }), let b = t.lastIndex(where: { $0.e > activeLevel }) else { return "" }
    let ps = pauses(t), end = ending(t)
    let p = ps.isEmpty ? "no pauses" : "\(ps.count) pause\(ps.count > 1 ? "s" : "") (" + ps.map { String(format: "%.1fs", $0.1 - $0.0) }.joined(separator: ", ") + ")"
    return String(format: "%.1fs of speech · ", t[b].x - t[a].x) + p + (end.isEmpty ? "" : " · ends " + end)
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
