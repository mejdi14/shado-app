import SwiftUI

// MARK: Mouth guide: a glowing cutaway head that shows how each sound of the example is usually made.
// The look follows Chimera by Jameson Hodge (github.com/jamesondh/chimera-vocal-synth, MIT); the drawing and sound table here are simplified and our own.

// MARK: Word to sounds (Apple phoneme symbols): the CMU Pronouncing Dictionary first (mac/cmudict.dict, copied into the app by Build Mac App.command; licence in mac/CMUDICT-LICENSE.txt), then rough spelling rules for words it doesn't list

enum CMUDict {
    static let entries: [String: String] = {
        guard let url = Bundle.main.url(forResource: "cmudict", withExtension: "dict"), let data = try? Data(contentsOf: url) else { return [:] }
        var out: [String: String] = [:]
        out.reserveCapacity(130_000)
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let sp = line.firstIndex(of: " ") else { continue }
            let word = line[..<sp]
            if word.hasSuffix(")") { continue }
            out[String(word)] = (line[line.index(after: sp)...].split(separator: "#").first ?? "").trimmingCharacters(in: .whitespaces)
        }
        return out
    }()
    static let arpa: [String: [String]] = [
        "AA": ["AA"], "AE": ["AE"], "AO": ["AO"], "AW": ["AW"], "AY": ["AY"], "EH": ["EH"], "ER": ["AX", "r"], "EY": ["EY"], "IH": ["IH"], "IY": ["IY"], "OW": ["OW"], "OY": ["OY"], "UH": ["UH"], "UW": ["UW"],
        "B": ["b"], "CH": ["C"], "D": ["d"], "DH": ["D"], "F": ["f"], "G": ["g"], "HH": ["h"], "JH": ["J"], "K": ["k"], "L": ["l"], "M": ["m"], "N": ["n"], "NG": ["N"], "P": ["p"],
        "R": ["r"], "S": ["s"], "SH": ["S"], "T": ["t"], "TH": ["T"], "V": ["v"], "W": ["w"], "Y": ["y"], "Z": ["z"], "ZH": ["Z"],
    ]
    static func sounds(_ word: String) -> [String]? {
        guard let e = entries[word] else { return nil }
        return e.split(separator: " ").flatMap { ph -> [String] in
            let base = String(ph.filter { $0.isLetter })
            if base == "AH" { return [ph.hasSuffix("0") ? "AX" : "UX"] }
            if base == "IH" && ph.hasSuffix("0") { return ["IX"] }
            return arpa[base] ?? []
        }
    }
}

func wordSounds(_ raw: String) -> [String] {
    let w = raw.lowercased().replacingOccurrences(of: "’", with: "'").filter { $0.isLetter || $0 == "'" || $0 == "-" }
    return w.split(separator: "-").flatMap { part -> [String] in
        let bare = part.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        return CMUDict.sounds(String(part)) ?? CMUDict.sounds(bare) ?? spelledSounds(bare)
    }
}

private let spelledExceptions: [String: [String]] = [
    "the": ["D", "AX"], "a": ["AX"], "an": ["AE", "n"], "of": ["AX", "v"], "to": ["t", "UW"],
    "you": ["y", "UW"], "your": ["y", "AO", "r"], "are": ["AA", "r"], "is": ["IH", "z"], "his": ["h", "IH", "z"],
    "was": ["w", "AX", "z"], "were": ["w", "AX", "r"], "do": ["d", "UW"], "does": ["d", "UX", "z"],
    "said": ["s", "EH", "d"], "says": ["s", "EH", "z"], "have": ["h", "AE", "v"], "one": ["w", "UX", "n"],
    "two": ["t", "UW"], "once": ["w", "UX", "n", "s"], "who": ["h", "UW"], "what": ["w", "UX", "t"],
    "where": ["w", "EH", "r"], "there": ["D", "EH", "r"], "their": ["D", "EH", "r"], "they": ["D", "EY"],
    "been": ["b", "IH", "n"], "could": ["k", "UH", "d"], "would": ["w", "UH", "d"], "should": ["S", "UH", "d"],
    "people": ["p", "IY", "p", "AX", "l"], "any": ["EH", "n", "IY"], "many": ["m", "EH", "n", "IY"],
    "very": ["v", "EH", "r", "IY"], "every": ["EH", "v", "r", "IY"], "come": ["k", "UX", "m"],
    "some": ["s", "UX", "m"], "done": ["d", "UX", "n"], "gone": ["g", "AO", "N"], "love": ["l", "UX", "v"],
    "move": ["m", "UW", "v"], "laugh": ["l", "AE", "f"], "eye": ["AY"], "i": ["AY"],
    "again": ["AX", "g", "EH", "n"], "friend": ["f", "r", "EH", "n", "d"],
    "because": ["b", "IH", "k", "AO", "z"], "about": ["AX", "b", "AW", "t"], "know": ["n", "OW"],
    "through": ["T", "r", "UW"], "though": ["D", "OW"], "thought": ["T", "AO", "t"],
]

func spelledSounds(_ word: String) -> [String] {
    let w = Array(word.lowercased().filter { $0.isASCII && $0.isLetter })
    let n = w.count
    guard n > 0 else { return [] }
    if let e = spelledExceptions[String(w)] { return e }
    let vow: Set<Character> = ["a", "e", "i", "o", "u"]
    let long: [Character: String] = ["a": "EY", "e": "IY", "i": "AY", "o": "OW", "u": "UW"]
    let short: [Character: String] = ["a": "AE", "e": "EH", "i": "IH", "o": "AA", "u": "UX"]
    let cons: [Character: [String]] = ["b": ["b"], "d": ["d"], "f": ["f"], "h": ["h"], "j": ["J"], "k": ["k"], "l": ["l"], "m": ["m"], "n": ["n"], "p": ["p"], "q": ["k"], "r": ["r"], "t": ["t"], "v": ["v"], "w": ["w"], "x": ["k", "s"], "z": ["z"]]
    let softD: Set<String> = ["the", "this", "that", "these", "those", "them", "then", "there", "their", "they", "though", "than", "with"]
    let hardG: Set<String> = ["get", "give", "girl", "begin", "together"]
    let isTh = softD.contains(String(w)), isHardG = hardG.contains(String(w))
    func isV(_ k: Int) -> Bool { k >= 0 && k < n && (vow.contains(w[k]) || (w[k] == "y" && k > 0)) }
    func at(_ k: Int) -> Character { k >= 0 && k < n ? w[k] : "\0" }
    let dropE = n > 2 && w[n - 1] == "e" && !isV(n - 2) && (0..<(n - 1)).contains { isV($0) }
    let leEnd = dropE && n > 3 && w[n - 2] == "l" && !isV(n - 3)
    let lim = leEnd ? n - 2 : (dropE ? n - 1 : n)
    var syl = leEnd ? 1 : 0
    for k in 0..<lim where isV(k) && !isV(k - 1) { syl += 1 }
    var o: [String] = []
    var i = 0
    func has(_ s: String) -> Bool { let a = Array(s); return i + a.count <= lim && Array(w[i..<(i + a.count)]) == a }
    func voiced() -> Bool { guard let l = o.last else { return false }; return !["C", "f", "h", "k", "p", "s", "S", "t", "T"].contains(l) }
    while i < lim {
        let c = w[i]
        var p: [String] = []
        var s = 1
        if i == 0 && (has("kn") || has("gn")) { p = ["n"]; s = 2 }
        else if i == 0 && has("wr") { p = ["r"]; s = 2 }
        else if i == 0 && c == "x" { p = ["z"] }
        else if has("tch") { p = ["C"]; s = 3 }
        else if has("ch") { p = ["C"]; s = 2 }
        else if has("sh") { p = ["S"]; s = 2 }
        else if has("th") { p = [isTh ? "D" : "T"]; s = 2 }
        else if has("ph") { p = ["f"]; s = 2 }
        else if has("wh") { p = ["w"]; s = 2 }
        else if has("ck") { p = ["k"]; s = 2 }
        else if has("ng") { p = ["N"]; s = 2 }
        else if has("nk") { p = ["N", "k"]; s = 2 }
        else if has("qu") { p = ["k", "w"]; s = 2 }
        else if has("ough") && i + 4 == lim { p = ["UX", "f"]; s = 4 }
        else if has("igh") { p = ["AY"]; s = 3 }
        else if has("gh") { p = i == 0 ? ["g"] : []; s = 2 }
        else if has("mb") && i + 2 == lim { p = ["m"]; s = 2 }
        else if has("dg") && "eiy".contains(at(i + 2)) { p = ["J"]; s = 2 }
        else if has("tion") { p = ["S", "AX", "n"]; s = 4 }
        else if has("sion") { p = [isV(i - 1) ? "Z" : "S", "AX", "n"]; s = 4 }
        else if !isV(i) && i + 1 < lim && at(i + 1) == c && c != "y" { s = 1 }
        else if c == "c" { p = ["eiy".contains(at(i + 1)) ? "s" : "k"] }
        else if c == "g" { p = ["eiy".contains(at(i + 1)) && !isHardG ? "J" : "g"] }
        else if c == "s" {
            if isV(i - 1) && at(i + 1) == "u" && at(i + 2) == "r" { p = ["Z"] }
            else if isV(i - 1) && i + 1 < lim && isV(i + 1) { p = ["z"] }
            else if dropE && i == lim - 1 { p = [isV(i - 1) && at(i - 1) != "u" ? "z" : "s"] }
            else if i == n - 1 && voiced() && !"uis".contains(at(i - 1)) { p = ["z"] }
            else { p = ["s"] }
        }
        else if c == "y" { p = [i == 0 ? "y" : (i == n - 1 ? (syl <= 1 ? "AY" : "IY") : "IH")] }
        else if !vow.contains(c) { p = cons[c] ?? [] }
        else {
            let single = !isV(i - 1) && !isV(i + 1)
            let magic = single && ((dropE && !leEnd && i + 2 == lim) || ("aou".contains(c) && String(w[(i + 1)..<min(i + 5, lim)]) == "tion"))
            if magic { p = [long[c] ?? "AX"] }
            else if (has("all") || has("alk") || has("alt")) && i + 3 == lim { p = has("all") ? ["AO", "l"] : (has("alk") ? ["AO", "k"] : ["AO", "l", "t"]); s = 3 }
            else if has("ee") || has("ea") { p = ["IY"]; s = 2 }
            else if has("ai") || has("ay") { p = ["EY"]; s = 2 }
            else if has("oa") { p = ["OW"]; s = 2 }
            else if has("ow") { p = [i + 2 == lim ? "OW" : "AW"]; s = 2 }
            else if has("oo") { p = ["UW"]; s = 2 }
            else if has("ou") { p = ["AW"]; s = 2 }
            else if has("oi") || has("oy") { p = ["OY"]; s = 2 }
            else if has("au") || has("aw") { p = ["AO"]; s = 2 }
            else if has("ie") { p = [i + 2 == lim && syl <= 1 ? "AY" : "IY"]; s = 2 }
            else if has("ei") { p = ["EY"]; s = 2 }
            else if has("ue") || has("ew") { p = ["UW"]; s = 2 }
            else if has("ey") && i + 2 == lim { p = ["IY"]; s = 2 }
            else if has("ar") { p = ["AA", "r"]; s = 2 }
            else if has("or") { p = ["AO", "r"]; s = 2 }
            else if has("er") || has("ir") || has("ur") { p = ["AX", "r"]; s = 2 }
            else if i == n - 1 { p = [c == "a" ? "AX" : (c == "o" || c == "u" ? long[c]! : "IY")] }
            else { p = [short[c] ?? "AX"] }
        }
        o += p
        i += s
    }
    if leEnd { o += ["AX", "l"] }
    if n > 3, w[n - 2] == "e", w[n - 1] == "d", Array(o.suffix(2)) == ["EH", "d"] {
        o.removeLast(2)
        let l = o.last ?? ""
        o += ["t", "d"].contains(l) ? ["IX", "d"] : ["p", "k", "f", "s", "S", "C", "T"].contains(l) ? ["t"] : ["d"]
    }
    return o
}

// MARK: Sound targets

enum Ch: Int, CaseIterable { case jaw, close, round, spread, tipUp, tipFront, high, front, velum, labio, voice }
typealias Target = [Ch: Double]

struct Artic {
    let jaw, close, round, spread, tipUp, tipFront, high, front, velum, labio, voice: Double
    init(_ v: [Double]) { jaw = v[0]; close = v[1]; round = v[2]; spread = v[3]; tipUp = v[4]; tipFront = v[5]; high = v[6]; front = v[7]; velum = v[8]; labio = v[9]; voice = v[10] }
}

struct MouthSound { let ipa: String; let hint: String; let parts: [Target] }

enum MouthSounds {
    static let rest: Target = [.jaw: 0.06, .close: 0.6, .round: 0.1, .spread: 0, .tipUp: 0, .tipFront: 0, .high: 0.35, .front: 0.5, .velum: 1, .labio: 0, .voice: 0]
    static func v(_ jaw: Double, _ high: Double, _ front: Double, round: Double = 0, spread: Double = 0) -> Target {
        [.jaw: jaw, .high: high, .front: front, .round: round, .spread: spread, .close: 0, .tipUp: 0, .tipFront: 0, .velum: 0, .labio: 0, .voice: 1]
    }
    static func c(_ voice: Double, _ t: Target) -> Target { var o: Target = [.velum: 0, .close: 0, .labio: 0]; o.merge(t) { $1 }; o[.voice] = voice; return o }
    static let sib: Target = [.tipUp: 0.8, .tipFront: 0, .jaw: 0.06, .spread: 0.3, .high: 0.55, .front: 0.75]
    static let hush: Target = [.tipUp: 0.6, .tipFront: 0, .high: 0.75, .front: 0.72, .round: 0.6, .jaw: 0.1]
    static let stop: Target = [.tipUp: 1, .tipFront: 0, .high: 0.6, .front: 0.7, .round: 0.3, .jaw: 0.1]
    static let velar: Target = [.high: 1, .front: 0.05, .jaw: 0.2, .tipUp: 0, .tipFront: 0]
    static let table: [String: MouthSound] = [
        "IY": .init(ipa: "iː", hint: "Tongue high and forward, lips spread", parts: [v(0.08, 1, 1, spread: 0.8)]),
        "IH": .init(ipa: "ɪ", hint: "Relaxed, tongue high and forward", parts: [v(0.18, 0.78, 0.85, spread: 0.4)]),
        "IX": .init(ipa: "ɪ", hint: "Short and relaxed", parts: [v(0.18, 0.7, 0.7, spread: 0.2)]),
        "EY": .init(ipa: "eɪ", hint: "Glide from “eh” towards “ee”", parts: [v(0.3, 0.6, 0.9, spread: 0.4), v(0.12, 0.92, 0.95, spread: 0.6)]),
        "EH": .init(ipa: "e", hint: "Jaw a little open, tongue forward", parts: [v(0.4, 0.5, 0.8, spread: 0.35)]),
        "AE": .init(ipa: "æ", hint: "Jaw open, tongue low and forward", parts: [v(0.75, 0.2, 0.75, spread: 0.5)]),
        "AA": .init(ipa: "ɑː", hint: "Jaw wide open, tongue low and back", parts: [v(0.95, 0.05, 0.15)]),
        "AO": .init(ipa: "ɔː", hint: "Jaw open, lips a little round", parts: [v(0.7, 0.2, 0.08, round: 0.55)]),
        "OW": .init(ipa: "oʊ", hint: "Round lips, closing towards “oo”", parts: [v(0.5, 0.45, 0.15, round: 0.7), v(0.22, 0.75, 0.1, round: 0.95)]),
        "UH": .init(ipa: "ʊ", hint: "Lips loosely round, tongue high and back", parts: [v(0.28, 0.7, 0.22, round: 0.6)]),
        "UW": .init(ipa: "uː", hint: "Lips round and pushed forward, tongue back", parts: [v(0.14, 0.95, 0.08, round: 1)]),
        "AX": .init(ipa: "ə", hint: "Short and relaxed, mouth half open", parts: [v(0.32, 0.45, 0.5)]),
        "UX": .init(ipa: "ʌ", hint: "Jaw half open, tongue relaxed", parts: [v(0.55, 0.3, 0.4)]),
        "AY": .init(ipa: "aɪ", hint: "Glide from “ah” towards “ee”", parts: [v(0.85, 0.1, 0.4), v(0.2, 0.85, 0.9, spread: 0.4)]),
        "AW": .init(ipa: "aʊ", hint: "Glide from “ah” towards “oo”", parts: [v(0.85, 0.1, 0.35), v(0.25, 0.7, 0.15, round: 0.85)]),
        "OY": .init(ipa: "ɔɪ", hint: "Glide from “aw” towards “ee”", parts: [v(0.6, 0.25, 0.1, round: 0.6), v(0.18, 0.85, 0.9, spread: 0.3)]),
        "p": .init(ipa: "p", hint: "Lips together, then a small puff", parts: [c(0, [.close: 1, .jaw: 0.1])]),
        "b": .init(ipa: "b", hint: "Lips together, voice on", parts: [c(1, [.close: 1, .jaw: 0.1])]),
        "m": .init(ipa: "m", hint: "Lips together, hum through the nose", parts: [c(1, [.close: 1, .jaw: 0.1, .velum: 1])]),
        "f": .init(ipa: "f", hint: "Top teeth on the lower lip, blow", parts: [c(0, [.labio: 1, .jaw: 0.12, .round: 0])]),
        "v": .init(ipa: "v", hint: "Top teeth on the lower lip, voice on", parts: [c(1, [.labio: 1, .jaw: 0.12, .round: 0])]),
        "T": .init(ipa: "θ", hint: "Tongue tip between the teeth, blow", parts: [c(0, [.tipFront: 1, .tipUp: 0, .jaw: 0.18])]),
        "D": .init(ipa: "ð", hint: "Tongue tip between the teeth, voice on", parts: [c(1, [.tipFront: 1, .tipUp: 0, .jaw: 0.18])]),
        "t": .init(ipa: "t", hint: "Tongue tip on the ridge behind the top teeth", parts: [c(0, [.tipUp: 1, .tipFront: 0, .jaw: 0.12])]),
        "d": .init(ipa: "d", hint: "Tongue tip on the ridge, voice on", parts: [c(1, [.tipUp: 1, .tipFront: 0, .jaw: 0.12])]),
        "n": .init(ipa: "n", hint: "Tongue tip on the ridge, air through the nose", parts: [c(1, [.tipUp: 1, .tipFront: 0, .jaw: 0.12, .velum: 1])]),
        "l": .init(ipa: "l", hint: "Tongue tip up, air flows round the sides", parts: [c(1, [.tipUp: 1, .tipFront: 0, .jaw: 0.22])]),
        "s": .init(ipa: "s", hint: "Tongue tip close to the ridge, a thin hiss", parts: [c(0, sib)]),
        "z": .init(ipa: "z", hint: "Like s, with voice on (a buzz)", parts: [c(1, sib)]),
        "S": .init(ipa: "ʃ", hint: "Lips forward, tongue raised behind the ridge", parts: [c(0, hush)]),
        "Z": .init(ipa: "ʒ", hint: "Like “sh”, with voice on", parts: [c(1, hush)]),
        "C": .init(ipa: "tʃ", hint: "Tongue tip up, then release into “sh”", parts: [c(0, stop), c(0, hush)]),
        "J": .init(ipa: "dʒ", hint: "Like “ch”, with voice on", parts: [c(1, stop), c(1, hush)]),
        "k": .init(ipa: "k", hint: "Back of the tongue against the soft palate", parts: [c(0, velar)]),
        "g": .init(ipa: "g", hint: "Back of the tongue up, voice on", parts: [c(1, velar)]),
        "N": .init(ipa: "ŋ", hint: "Back of the tongue up, air through the nose", parts: [c(1, velar.merging([.velum: 1]) { $1 })]),
        "h": .init(ipa: "h", hint: "An open breath, mouth ready for the next sound", parts: [c(0, [.tipUp: 0, .tipFront: 0])]),
        "r": .init(ipa: "r", hint: "Tongue pulled back and up, lips a little round", parts: [c(1, [.round: 0.5, .tipUp: 0.45, .tipFront: 0, .high: 0.6, .front: 0.45, .jaw: 0.18])]),
        "w": .init(ipa: "w", hint: "Lips small and round, then open", parts: [c(1, [.round: 1, .close: 0.35, .high: 0.85, .front: 0.1, .jaw: 0.1, .tipUp: 0, .tipFront: 0])]),
        "y": .init(ipa: "j", hint: "Tongue high and forward, like a quick “ee”", parts: [c(1, [.high: 1, .front: 1, .spread: 0.45, .jaw: 0.08, .round: 0, .tipUp: 0, .tipFront: 0])]),
    ]
}

// MARK: Timeline: each word's sounds spread over its transcript timing, eased from one target to the next

struct MouthSeg { let start, end: Double; let sound, word: String }

struct MouthTimeline {
    var keys = [[(t: Double, v: Double)]](repeating: [], count: Ch.allCases.count)
    var segs: [MouthSeg] = []

    init() {}
    init(_ phrase: Phrase) {
        var words = (phrase.words ?? []).map { ($0.start, $0.end, $0.word) }.filter { $0.2.contains { $0.isLetter } }
        if words.isEmpty {
            let toks = phrase.text.split { !$0.isLetter && $0 != "'" && $0 != "’" }.map(String.init)
            let total = Double(max(1, toks.reduce(0) { $0 + $1.count })), span = max(0.1, phrase.end - phrase.start - 0.2)
            var at = phrase.start + 0.1
            for w in toks { let d = span * Double(w.count) / total; words.append((at, at + d, w)); at += d }
        }
        var lastEnd: Double? = nil
        for (start, end, raw) in words {
            let sounds = wordSounds(raw).filter { MouthSounds.table[$0] != nil }
            guard !sounds.isEmpty, end > start else { continue }
            if let le = lastEnd { if start - le > 0.25 { add(MouthSounds.rest, le + 0.1); add(MouthSounds.rest, start - 0.1) } }
            else { add(MouthSounds.rest, start - 0.15) }
            let weights = sounds.map { s -> Double in s.count == 2 ? 1.7 : ["p", "b", "t", "d", "k", "g"].contains(s) ? 0.75 : 1 }
            let total = weights.reduce(0, +), label = raw.filter { $0.isLetter || $0 == "'" || $0 == "’" }
            var at = start
            for (s, wt) in zip(sounds, weights) {
                let d = (end - start) * wt / total, parts = MouthSounds.table[s]!.parts
                for (k, p) in parts.enumerated() { add(p, at + d * (parts.count == 1 ? 0.5 : k == 0 ? 0.3 : 0.8)) }
                segs.append(MouthSeg(start: at, end: at + d, sound: s, word: label)); at += d
            }
            lastEnd = max(lastEnd ?? end, end)
        }
        if let le = lastEnd { add(MouthSounds.rest, le + 0.15) }
        for i in keys.indices { keys[i].sort { $0.t < $1.t } }
    }

    mutating func add(_ t: Target, _ at: Double) { for (c, v) in t { keys[c.rawValue].append((at, v)) } }

    func artic(_ t: Double) -> Artic {
        Artic(Ch.allCases.map { c in
            let k = keys[c.rawValue]
            guard let f = k.first, let l = k.last else { return MouthSounds.rest[c] ?? 0 }
            if t <= f.t { return f.v }
            if t >= l.t { return l.v }
            var lo = 0, hi = k.count - 1
            while hi - lo > 1 { let m = (lo + hi) / 2; if k[m].t <= t { lo = m } else { hi = m } }
            let x = k[hi].t > k[lo].t ? (t - k[lo].t) / (k[hi].t - k[lo].t) : 1
            return k[lo].v + (k[hi].v - k[lo].v) * x * x * (3 - 2 * x)
        })
    }

    func seg(_ t: Double) -> MouthSeg? { segs.first { t >= $0.start && t < $0.end } }
}

// MARK: Pose: the moving outlines, in a 240 × 250 side view facing right (y down), jaw turning about the condyle

struct MouthPose {
    let a: Artic
    var upperLip: [CGPoint] = [], lowerLip: [CGPoint] = [], chin: [CGPoint] = [], jaw: [CGPoint] = [], lowerTooth: [CGPoint] = [], tongue: [CGPoint] = [], velum: [CGPoint] = []
    var gap = 0.0
    var contacts: [(CGPoint, Double)] = []

    static let pivot = CGPoint(x: 120, y: 118)
    static func rot(_ p: CGPoint, _ th: Double) -> CGPoint {
        let dx = p.x - pivot.x, dy = p.y - pivot.y
        return CGPoint(x: pivot.x + dx * cos(th) - dy * sin(th), y: pivot.y + dx * sin(th) + dy * cos(th))
    }
    static let palate: [(Double, Double)] = [(131, 128), (138, 126), (150, 125), (162, 127), (170, 131), (174, 134)]
    static func palateY(_ x: Double) -> Double? {
        guard x >= palate[0].0, x <= palate[palate.count - 1].0 else { return nil }
        for i in 1..<palate.count where x <= palate[i].0 { let (x0, y0) = palate[i - 1], (x1, y1) = palate[i]; return y0 + (y1 - y0) * (x - x0) / (x1 - x0) }
        return nil
    }
    static func ease(_ a: Double, _ b: Double, _ x: Double) -> Double { let t = min(1, max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t) }

    init(_ a: Artic) {
        self.a = a
        let th = a.jaw * 0.2, p = MouthHead.p, mix = MouthHead.mix
        func r(_ x: Double, _ y: Double, _ k: Double = 1) -> CGPoint { MouthPose.rot(CGPoint(x: x, y: y), th * k) }
        func onPalate(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x, y: max(q.y, (MouthPose.palateY(q.x) ?? -1e9) + 1.5)) }
        let dx = a.round * 6 - a.spread * 2, uy = 144 + 0.8 * a.close
        upperLip = [p(187, 130), p(191 + dx * 0.7, 136), p(194 + dx, 141), p(190 + dx, uy), p(184 + dx * 0.5, uy - 0.6)]
        var ll = [r(184, 148), r(190, 148.5), r(193, 152), r(190, 158), r(186, 162)]
        let dy = (uy + 0.6 - ll[1].y) * a.close, lift = [1, 1, 1, 0.6, 0.3], fwd = [0.5, 1, 1, 0.6, 0]
        for i in ll.indices { ll[i].y += dy * lift[i]; ll[i].x += dx * fwd[i] }
        let tucked = [p(178, 149), p(182, 147.6), p(187, 151), p(186, 157), ll[4]]
        for i in ll.indices { ll[i] = mix(ll[i], tucked[i], a.labio) }
        lowerLip = ll
        gap = max(0, ll[1].y - uy - 0.6)
        chin = [ll[4], r(190, 172), r(184, 183), r(166, 189), r(150, 192), p(138, 199), p(134, 215), p(132, 250)]
        jaw = [r(120, 118), r(117, 132), r(118, 152), r(123, 170), r(140, 180), r(160, 182), r(176, 178), r(183, 170), r(181, 162), r(176, 160)]
        lowerTooth = [r(174, 161), r(177, 160), r(180, 149), r(177.5, 148.5), r(173.5, 153)]
        let f = a.front, h = a.high, c0 = p(134 + 22 * f, 146 - 18 * h)
        let body = onPalate(MouthPose.rot(c0, th * 0.55))
        let dorsum = onPalate(MouthPose.rot(p(c0.x - 15 + 3 * f, c0.y + 7 - 3 * h), th * 0.45))
        let back = MouthPose.rot(p(111 + 13 * f + 3 * h, 160 - 5 * h), th * 0.25), root = MouthPose.rot(p(121 + 4 * f, 182), th * 0.15)
        var tip = mix(r(171, 150), p(171.5, 134.5), a.tipUp)
        tip = mix(tip, p(182.5, 148.5), a.tipFront)
        let blade = onPalate(mix(MouthPose.rot(p(min(167, c0.x + 13), c0.y + 4 + 3 * (1 - h)), th * 0.7), p(tip.x - 9, tip.y + 2.5), max(a.tipUp, a.tipFront) * 0.6))
        tongue = [root, back, dorsum, body, blade, tip, p(tip.x - 3, tip.y + 4.5), r(163, 159), r(147, 166, 0.9), r(131, 174, 0.5)]
        velum = [p(131, 128), mix(p(122, 128.5), p(127, 137), a.velum), mix(p(109.5, 130), p(123, 146), a.velum)]
        let e = MouthPose.ease
        contacts = [
            (p(191 + dx, uy + 0.3), e(0.7, 0.98, a.close) * (1 - a.labio)),
            (p(181, 147.4), e(0.6, 0.95, a.labio)),
            (p(171.5, 133.5), e(0.75, 0.98, a.tipUp)),
            (p(182, 147.6), e(0.6, 0.95, a.tipFront)),
            (p(body.x, body.y - 2), e(0.85, 0.99, h) * e(0.35, 0.1, f)),
        ]
    }
}

// MARK: Drawing

enum MouthHead {
    static let skull = Color(red: 0.35, green: 0.72, blue: 1), soft = Color(red: 0.62, green: 0.86, blue: 1), jawC = Color(red: 1, green: 0.38, blue: 0.3)
    static let tongueC = Color(red: 0.42, green: 1, blue: 0.55), lipC = Color(red: 1, green: 0.45, blue: 0.78), toothC = Color(white: 0.93), voiceC = Color(red: 1, green: 0.84, blue: 0.35)
    static func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
    static func mix(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
    static func pts(_ v: [(Double, Double)]) -> [CGPoint] { v.map { p($0.0, $0.1) } }

    static let head = pts([(181, 92), (185, 72), (180, 50), (164, 28), (138, 14), (106, 13), (76, 26), (56, 48), (46, 76), (47, 104), (55, 130), (68, 152), (78, 172), (80, 200), (80, 250)])
    static let brain = pts([(174, 70), (168, 44), (152, 28), (128, 21), (102, 21), (80, 32), (63, 52), (56, 78), (59, 102), (70, 120)])
    static let rings: [[CGPoint]] = [pts([(72, 34), (120, 41), (168, 34)]), pts([(52, 58), (118, 65), (181, 58)]), pts([(46, 84), (116, 91), (183, 84)]), pts([(122, 14), (104, 40), (96, 76), (100, 108)]), pts([(122, 14), (144, 40), (156, 76), (160, 104)])]
    static let nose = pts([(181, 92), (190, 104), (199, 116), (204, 123), (200, 128.5), (193, 130.5), (187, 130)])
    static let nasal = pts([(194, 125), (184, 112), (164, 104), (138, 102), (116, 106), (108, 116)])
    static let nasalFloor = pts([(189, 129), (172, 126.5), (150, 121), (132, 122), (118, 123)])
    static let pharynx = pts([(110, 106), (107, 128), (106, 150), (108, 175), (111, 198), (112, 218), (112, 250)])
    static let larynx = pts([(126, 192), (129, 204), (128, 250)])
    static let epiglottis = pts([(128, 171), (124, 180), (121, 189)])
    static let upperTooth = pts([(173, 133), (178, 134), (181, 146.5), (178, 147.5), (174, 140)])

    static func curve(_ q: [CGPoint], closed: Bool = false) -> Path {
        var path = Path()
        let n = q.count
        guard n > 1 else { return path }
        path.move(to: q[0])
        for i in 0..<(closed ? n : n - 1) {
            let a = q[closed ? (i - 1 + n) % n : max(i - 1, 0)], b = q[i], c = q[(i + 1) % n], d = q[closed ? (i + 2) % n : min(i + 2, n - 1)]
            path.addCurve(to: c, control1: CGPoint(x: b.x + (c.x - a.x) / 6, y: b.y + (c.y - a.y) / 6), control2: CGPoint(x: c.x - (d.x - b.x) / 6, y: c.y - (d.y - b.y) / 6))
        }
        if closed { path.closeSubpath() }
        return path
    }
    static func poly(_ q: [CGPoint]) -> Path { var path = Path(); path.addLines(q); path.closeSubpath(); return path }
    static func glow(_ g: GraphicsContext, _ path: Path, _ c: Color, _ w: CGFloat = 1.3, _ k: Double = 1) {
        for (width, alpha) in [(w * 4.5, 0.14), (w * 2.2, 0.32), (w, 1.0)] {
            g.stroke(path, with: .color(c.opacity(alpha * k)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
    }

    static func draw(_ g: GraphicsContext, _ size: CGSize, _ pose: MouthPose, _ clock: Double) {
        let k = min(size.width / 172, size.height / 244), ox = (size.width - 172 * k) / 2 - 40 * k, oy = (size.height - 244 * k) / 2 - 6 * k
        func m(_ q: [CGPoint]) -> [CGPoint] { q.map { CGPoint(x: ox + $0.x * k, y: oy + $0.y * k) } }
        let a = pose.a
        for ring in rings { glow(g, curve(m(ring)), skull, 1, 0.12) }
        glow(g, curve(m(brain)), skull, 1, 0.3)
        glow(g, Path(ellipseIn: CGRect(x: ox + 92 * k, y: oy + 84 * k, width: 15 * k, height: 30 * k)), skull, 1, 0.35)
        glow(g, Path(ellipseIn: CGRect(x: ox + 165 * k, y: oy + 77 * k, width: 11 * k, height: 6 * k)), skull, 1, 0.6)
        glow(g, curve(m(head)), skull)
        glow(g, curve(m(nose)), skull)
        glow(g, curve(m(nasal)), soft, 1, 0.25 + 0.75 * a.velum * a.voice)
        glow(g, curve(m(nasalFloor)), soft, 1, 0.25)
        glow(g, curve(m(pharynx)), skull, 1.2, 0.8)
        glow(g, curve(m(larynx)), skull, 1.2, 0.6)
        glow(g, curve(m(epiglottis)), soft, 1.2, 0.8)
        let half = 3.5 * (1 - a.voice) + a.voice * (0.8 + 0.5 * sin(clock * .pi * 2 * 9))
        glow(g, curve(m(pts([(112.5, 205), (120 - half, 206)]))), voiceC, 1.4, 0.3 + 0.7 * a.voice)
        glow(g, curve(m(pts([(128, 205), (120 + half, 206)]))), voiceC, 1.4, 0.3 + 0.7 * a.voice)
        if a.voice > 0.05 { g.fill(Path(ellipseIn: CGRect(x: ox + 112 * k, y: oy + 198 * k, width: 16 * k, height: 14 * k)), with: .color(voiceC.opacity(0.16 * a.voice))) }
        glow(g, curve(m(pts(MouthPose.palate.reversed()))), soft, 1.6)
        glow(g, curve(m(pose.velum)), soft, 2.4)
        glow(g, curve(m(pose.jaw)), jawC, 1.2, 0.9)
        glow(g, curve(m(pose.chin)), skull)
        glow(g, poly(m(upperTooth)), toothC, 1.1)
        glow(g, poly(m(pose.lowerTooth)), toothC, 1.1)
        let tongue = curve(m(pose.tongue), closed: true)
        g.fill(tongue, with: .color(tongueC.opacity(0.12)))
        glow(g, tongue, tongueC, 1.4)
        glow(g, curve(m(pose.upperLip)), lipC, 1.5)
        glow(g, curve(m(pose.lowerLip)), lipC, 1.5)
        for (q, on) in pose.contacts where on > 0.02 {
            let c = m([q])[0]
            g.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(.white.opacity(0.18 * on)))
            g.fill(Path(ellipseIn: CGRect(x: c.x - 2.2, y: c.y - 2.2, width: 4.4, height: 4.4)), with: .color(.white.opacity(on)))
        }
    }

    static func drawLips(_ g: GraphicsContext, _ size: CGSize, _ pose: MouthPose) {
        let a = pose.a, cx = size.width / 2, cy = size.height / 2
        let w = 30 * (1 - 0.4 * a.round + 0.2 * a.spread), h = min(20, pose.gap * 1.6 + (pose.gap > 0.5 ? a.round * 5 : 0))
        let outer = curve([p(cx - w / 2 - 8, cy), p(cx - w / 4, cy - h / 2 - 7), p(cx, cy - h / 2 - 5.5), p(cx + w / 4, cy - h / 2 - 7), p(cx + w / 2 + 8, cy), p(cx + w / 4, cy + h / 2 + 8), p(cx - w / 4, cy + h / 2 + 8)], closed: true)
        glow(g, outer, lipC, 1.3)
        if h < 1.5 {
            glow(g, curve([p(cx - w / 2 - 6, cy), p(cx + w / 2 + 6, cy)]), lipC, 1.1, 0.8)
        } else {
            let open = Path(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
            g.fill(open, with: .color(.black))
            var inner = g
            inner.clip(to: open)
            if a.labio < 0.5 { inner.fill(Path(CGRect(x: cx - w * 0.35, y: cy - h / 2 - 1, width: w * 0.7, height: min(4.5, h * 0.45))), with: .color(toothC.opacity(0.75))) }
            if a.tipFront > 0.4 { inner.fill(Path(ellipseIn: CGRect(x: cx - 7, y: cy - 2, width: 14, height: 6)), with: .color(tongueC.opacity(0.6 * a.tipFront))) }
            glow(g, open, lipC, 1, 0.7)
        }
        if a.labio > 0.4 { g.fill(Path(roundedRect: CGRect(x: cx - 9, y: cy - 1, width: 18, height: 4), cornerRadius: 1), with: .color(toothC.opacity(a.labio))) }
    }
}

// MARK: View

struct MouthGuide: View {
    @EnvironmentObject var s: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let phrase: Phrase
    @AppStorage("mouth-guide") private var shown = true
    @State private var line = MouthTimeline()
    var lineKey: String { "\(phrase.start)|\(phrase.end)|\(phrase.text)|\(phrase.words?.count ?? 0)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Mouth guide", systemImage: "mouth").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(shown ? "Hide" : "Show") { shown.toggle() }.buttonStyle(PillStyle(compact: true)).accessibilityLabel(shown ? "Hide mouth guide" : "Show mouth guide")
            }
            if shown {
                TimelineView(.animation(paused: reduceMotion || !s.isPlaying)) { tl in
                    let t = !reduceMotion && s.isPlaying ? (s.original?.currentTime ?? phrase.start) : phrase.start + s.position
                    let pose = MouthPose(line.artic(t)), clock = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                    HStack(alignment: .top, spacing: 0) {
                        Canvas { g, size in MouthHead.draw(g, size, pose, clock) }.frame(width: 210, height: 270)
                            .accessibilityLabel("Side view of a head showing the lips, tongue and jaw for the current sound")
                        info(line.seg(t), pose).padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.012, green: 0.02, blue: 0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(MouthHead.skull.opacity(0.28)))
                }
                muted("A rough guide from dictionary pronunciations (American English), timed to the transcript. It doesn’t track the speaker’s real mouth, so let your ears decide.").fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: lineKey) {
            let ph = phrase
            let next = await Task.detached(priority: .userInitiated) { MouthTimeline(ph) }.value
            if !Task.isCancelled { line = next }
        }
    }

    func info(_ seg: MouthSeg?, _ pose: MouthPose) -> some View {
        let snd = seg.flatMap { MouthSounds.table[$0.sound] }
        return VStack(alignment: .leading, spacing: 8) {
            Text("MOUTH GUIDE").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2.4).foregroundStyle(MouthHead.skull.opacity(0.85))
            Text(snd.map { "/\($0.ipa)/" } ?? "–").font(.system(size: 34, weight: .light, design: .rounded)).foregroundStyle(MouthHead.skull).shadow(color: MouthHead.skull.opacity(0.7), radius: 8)
            Text(snd?.hint ?? (reduceMotion ? "Use the position slider to inspect each sound." : s.isPlaying ? "Between words" : "Press Listen to watch each sound, or drag the position slider.")).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.82)).fixedSize(horizontal: false, vertical: true)
            if let seg, !s.concealed { Text("in “\(seg.word)”").font(.system(size: 13, weight: .medium)).foregroundStyle(MouthHead.lipC) }
            Spacer(minLength: 6)
            Canvas { g, size in MouthHead.drawLips(g, size, pose) }.frame(width: 96, height: 54).accessibilityHidden(true)
            Text("LIPS FROM THE FRONT").font(.system(size: 9, design: .monospaced)).tracking(1.6).foregroundStyle(Color.white.opacity(0.4))
            HStack(spacing: 10) { swatch("Lips", MouthHead.lipC); swatch("Tongue", MouthHead.tongueC); swatch("Jaw", MouthHead.jawC); swatch("Voice", MouthHead.voiceC) }
        }
    }

    func swatch(_ t: String, _ c: Color) -> some View { HStack(spacing: 4) { Circle().fill(c).frame(width: 6, height: 6); Text(t).font(.system(size: 10.5)).foregroundStyle(Color.white.opacity(0.6)) } }
}
