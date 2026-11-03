import Foundation

enum VoiceTechnique: String, CaseIterable, Identifiable {
    case pitch, intonation, stress, rhythm, pace, pauses, energy, articulation, connected
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pitch: return "Pitch"
        case .intonation: return "Intonation"
        case .stress: return "Stress"
        case .rhythm: return "Rhythm"
        case .pace: return "Pace"
        case .pauses: return "Pauses"
        case .energy: return "Energy"
        case .articulation: return "Articulation"
        case .connected: return "Connected Speech"
        }
    }
    var icon: String {
        switch self {
        case .pitch: return "waveform.path"
        case .intonation: return "point.topleft.down.curvedto.point.bottomright.up"
        case .stress: return "bold"
        case .rhythm: return "metronome"
        case .pace: return "speedometer"
        case .pauses: return "pause"
        case .energy: return "speaker.wave.2"
        case .articulation: return "text.bubble"
        case .connected: return "link"
        }
    }
    var explanation: String {
        switch self {
        case .pitch: return "Pitch is how high or low your voice sounds. Practise moving from your own comfortable note; you don’t need anyone else’s natural pitch."
        case .intonation: return "Intonation is the melody of a phrase. Follow the shape of the rise and fall, in a range that feels comfortable for you."
        case .stress: return "Stress makes one syllable or word stand out. Give it a little more strength, length, and clarity."
        case .rhythm: return "Speech has strong beats and softer syllables between them. Let the small syllables be lighter and shorter."
        case .pace: return "Pace is how quickly you speak. Learn to keep a steady speed before gradually increasing it."
        case .pauses: return "Group words that belong together, then leave a little space between groups. Speak in thoughts instead of pausing after every word."
        case .energy: return "Vocal energy is how strong or soft your voice feels. Practise relative changes at a comfortable volume, without pushing your voice."
        case .articulation: return "Articulation is how clearly you form sounds. Move deliberately and aim for clarity, rather than a perfect accent."
        case .connected: return "In natural speech, words flow into each other. Listen for links and shorter forms, then try the same connection yourself."
        }
    }
    var bridge: String {
        switch self {
        case .pitch: return "Later, pitch control helps you follow a speaker’s intonation."
        case .intonation: return "Later, you’ll use this melody across real shadowing phrases."
        case .stress: return "Later, emphasis helps you carry a speaker’s meaning."
        case .rhythm: return "Later, these strong and soft beats make shadowing feel easier."
        case .pace: return "Later, a steady pace helps you keep up with a speaker."
        case .pauses: return "Later, phrase groups help you follow longer sentences."
        case .energy: return "Later, energy adds expression to stressed words."
        case .articulation: return "Later, clear mouth movements help at a speaker’s normal speed."
        case .connected: return "Later, listening for links helps you imitate natural speech."
        }
    }
    var exercises: [VoiceExercise] { VoiceTrainingCatalog.exercises[self] ?? [] }
    var usesPitch: Bool { self == .pitch || self == .intonation }
    var selfReview: Bool { self == .articulation || self == .connected }
}

enum VoicePattern: String {
    case flat, rise, fall, arch, dip, alternate
    var anchors: [Double] {
        switch self {
        case .flat: return [0, 0, 0, 0, 0]
        case .rise: return [-2.5, -2.5, -1, 1, 3]
        case .fall: return [3, 2, 0, -2, -2.5]
        case .arch: return [-2, 0, 3, 0, -2]
        case .dip: return [2, 0, -3, 0, 2]
        case .alternate: return [-2, -2, 2, 2, -2, -2, 2, 2]
        }
    }
    func value(_ fraction: Double) -> Double { trainingSample(anchors, fraction) }
    var cue: String {
        switch self {
        case .flat: return "Keep it steady"
        case .rise: return "Let your voice rise"
        case .fall: return "Let your voice fall"
        case .arch: return "Rise, then fall"
        case .dip: return "Fall, then rise"
        case .alternate: return "Low → high → low → high"
        }
    }
}

func trainingSample(_ values: [Double], _ fraction: Double) -> Double {
    guard let first = values.first else { return 0 }
    if values.count == 1 { return first }
    let x = min(1, max(0, fraction)) * Double(values.count - 1), i = min(values.count - 2, Int(x)), f = x - Double(i)
    return values[i] * (1 - f) + values[i + 1] * f
}

struct VoiceExercise: Identifiable {
    let id: String
    let title: String
    let instruction: String
    let prompt: String
    var pattern: VoicePattern = .flat
    var duration: Double = 3
    var spoken: String? = nil
    var contrast: String? = nil
    var contrastLabel = "Hear contrast"
    var contrastPattern: VoicePattern = .flat
    var units: [String] = []
    var strong: [Int] = []
    var contrastStrong: [Int] = []
    var pauseAt: [Double] = []
    var rate: Float = 0.45
    var review: String = ""
    var isTone: Bool { spoken == nil }
    func key(_ technique: VoiceTechnique) -> String { technique.rawValue + "." + id }
}

struct TrainingProgress: Codable { var completed: [String] }

enum VoiceTrainingCatalog {
    static let exercises: [VoiceTechnique: [VoiceExercise]] = [
        .pitch: [
            VoiceExercise(id: "flat", title: "One comfortable note", instruction: "Say “ah” gently for about three seconds. Keep the note steady.", prompt: "ah ———", contrast: "tone", contrastLabel: "Hear a rise", contrastPattern: .rise),
            VoiceExercise(id: "rise", title: "A gentle rise", instruction: "Start with an easy “ah”, then slide your voice a little higher.", prompt: "ah ↗", pattern: .rise, contrast: "tone", contrastLabel: "Hear a flat note"),
            VoiceExercise(id: "fall", title: "A gentle fall", instruction: "Start a little higher in your comfortable range. Let “ah” glide down.", prompt: "ah ↘", pattern: .fall),
            VoiceExercise(id: "rise-fall", title: "Over the hill", instruction: "In one breath, let “ah” rise and gently fall again.", prompt: "ah ↗ ↘", pattern: .arch, duration: 4),
            VoiceExercise(id: "fall-rise", title: "Through the valley", instruction: "Let “ah” go down, then come back up. Keep the movement relaxed.", prompt: "ah ↘ ↗", pattern: .dip, duration: 4),
            VoiceExercise(id: "alternate", title: "Switch between notes", instruction: "Alternate between a comfortable low and high note, without straining.", prompt: "low · high · low · high", pattern: .alternate, duration: 4),
            VoiceExercise(id: "phrase", title: "Put it into a phrase", instruction: "Say “Here we go!” with a gentle rise. Keep your own natural voice.", prompt: "Here we go!", pattern: .rise, duration: 2, spoken: "Here we go!")
        ],
        .intonation: [
            VoiceExercise(id: "statement", title: "Finish a thought", instruction: "Say the statement and let your voice settle at the end.", prompt: "It’s finished.", pattern: .fall, duration: 2, spoken: "It's finished.", contrast: "It's finished?", contrastLabel: "Hear the question"),
            VoiceExercise(id: "question", title: "Ask a question", instruction: "Ask as if you’re checking surprising news. Lift the end gently.", prompt: "It’s finished?", pattern: .rise, duration: 2, spoken: "It's finished?", contrast: "It's finished.", contrastLabel: "Hear the statement"),
            VoiceExercise(id: "rise-fall", title: "Add a little expression", instruction: "Say “That’s amazing!” Let your voice rise in the middle, then settle.", prompt: "That’s amazing!", pattern: .arch, duration: 2.5, spoken: "That's amazing!"),
            VoiceExercise(id: "fall-rise", title: "Leave a thought open", instruction: "Say “Well, maybe…” as if you’re still deciding. Dip, then lift your voice.", prompt: "Well, maybe…", pattern: .dip, duration: 2.5, spoken: "Well, maybe?"),
            VoiceExercise(id: "expressive", title: "Bring the phrase to life", instruction: "Give “I really enjoyed it!” a rise and fall. Compare with the calmer example.", prompt: "I really enjoyed it!", pattern: .arch, spoken: "I really enjoyed it!", contrast: "I really enjoyed it.", contrastLabel: "Hear a calmer version")
        ],
        .stress: [
            VoiceExercise(id: "first-syllable", title: "Stress the first syllable", instruction: "Say the noun “present”, as in a gift. Make PRE stand out.", prompt: "PRE · sent", duration: 1.5, spoken: "present", contrast: "Present it.", contrastLabel: "Hear “present it”", units: ["PRE", "sent"], strong: [0], contrastStrong: [1]),
            VoiceExercise(id: "second-syllable", title: "Move the word stress", instruction: "Say “present it”, as in show it. Give SENT more strength and length.", prompt: "pre · SENT · it", duration: 2, spoken: "Present it.", units: ["pre", "SENT", "it"], strong: [1]),
            VoiceExercise(id: "really", title: "Emphasize how much", instruction: "Make REALLY the strongest word. You’re saying how much you like it.", prompt: "I REALLY like it.", duration: 2.5, spoken: "I really like it.", contrast: "I really like it.", contrastLabel: "Hear emphasis on LIKE", units: ["I", "REALLY", "like", "it"], strong: [1], contrastStrong: [2]),
            VoiceExercise(id: "like", title: "Emphasize the feeling", instruction: "Make LIKE stand out, as if someone thought you disliked it.", prompt: "I really LIKE it.", duration: 2.5, spoken: "I really like it.", units: ["I", "really", "LIKE", "it"], strong: [2]),
            VoiceExercise(id: "it", title: "Choose the important word", instruction: "Emphasize IT, as if you mean this particular thing.", prompt: "I really like IT.", duration: 2.5, spoken: "I really like it.", units: ["I", "really", "like", "IT"], strong: [3])
        ],
        .rhythm: [
            VoiceExercise(id: "two-beats", title: "Strong, soft", instruction: "Say DA da. Give the first syllable a beat and keep the next one light.", prompt: "DA da", duration: 2, units: ["DA", "da"], strong: [0]),
            VoiceExercise(id: "four-beats", title: "Repeat the pattern", instruction: "Say DA da DA da along with the pulse. Keep the small syllables short.", prompt: "DA da DA da", duration: 3, units: ["DA", "da", "DA", "da"], strong: [0, 2]),
            VoiceExercise(id: "two-soft", title: "Fit in the small syllables", instruction: "Say DA da da DA. Fit two light syllables between the strong beats.", prompt: "DA da da DA", duration: 3, units: ["DA", "da", "da", "DA"], strong: [0, 3]),
            VoiceExercise(id: "real-words", title: "Find the beats in words", instruction: "Give WANT, GO, and STORE the beats. Let the other words be lighter.", prompt: "I WANT to GO to the STORE.", duration: 3.5, spoken: "I want to go to the store.", units: ["I", "WANT", "to", "GO", "to", "the", "STORE"], strong: [1, 3, 6]),
            VoiceExercise(id: "sentence", title: "Keep a sentence moving", instruction: "Say the phrase with three clear beats. Avoid giving every word the same weight.", prompt: "We NEED a little MORE TIME.", spoken: "We need a little more time.", units: ["We", "NEED", "a", "little", "MORE", "TIME"], strong: [1, 4, 5])
        ],
        .pace: [
            VoiceExercise(id: "slow", title: "Start slowly", instruction: "Say the phrase slowly and evenly. Keep moving without adding long gaps.", prompt: "We can take it one step at a time.", duration: 5, spoken: "We can take it one step at a time.", rate: 0.35),
            VoiceExercise(id: "normal", title: "Find a natural pace", instruction: "Use the same sentence at a comfortable everyday speed.", prompt: "We can take it one step at a time.", duration: 3.8, spoken: "We can take it one step at a time."),
            VoiceExercise(id: "quicker", title: "A little quicker", instruction: "Say the same phrase a little faster, while keeping the words clear.", prompt: "We can take it one step at a time.", duration: 3.2, spoken: "We can take it one step at a time.", rate: 0.5),
            VoiceExercise(id: "steady", title: "Stay steady to the end", instruction: "Keep a similar pace across both halves. Don’t rush the final words.", prompt: "Every little step will help me learn.", duration: 3.2, spoken: "Every little step will help me learn.", units: ["Every little step", "will help me learn"]),
            VoiceExercise(id: "faster", title: "Build a little speed", instruction: "Try the shorter target time. Keep your mouth relaxed and the words clear.", prompt: "Every little step will help me learn.", duration: 2.7, spoken: "Every little step will help me learn.", rate: 0.53)
        ],
        .pauses: [
            VoiceExercise(id: "two-groups", title: "Two thoughts", instruction: "Say each group smoothly, with one short pause at the divider.", prompt: "Hello there / how are you?", spoken: "Hello there. How are you?", units: ["Hello there", "how are you?"], pauseAt: [0.45]),
            VoiceExercise(id: "place", title: "Keep words together", instruction: "Keep “at the station” together. Pause only between the two groups.", prompt: "When I arrived / at the station", duration: 3.5, spoken: "When I arrived, at the station.", units: ["When I arrived", "at the station"], pauseAt: [0.5]),
            VoiceExercise(id: "three-groups", title: "Three meaningful chunks", instruction: "Say the full thought in three groups. Leave a small space at each divider.", prompt: "When I arrived / at the station / nobody was there.", duration: 5.5, spoken: "When I arrived, at the station, nobody was there.", units: ["When I arrived", "at the station", "nobody was there."], pauseAt: [0.32, 0.63]),
            VoiceExercise(id: "intro", title: "Make room after an introduction", instruction: "Say the introduction as one chunk, pause briefly, then finish the sentence.", prompt: "After a long day / I like to read.", duration: 4, spoken: "After a long day, I like to read.", units: ["After a long day", "I like to read."], pauseAt: [0.48]),
            VoiceExercise(id: "list", title: "Let a list breathe", instruction: "Keep each group intact. Use two small pauses to organize the list.", prompt: "Bring your notebook / a pen / and a little curiosity.", duration: 4.5, spoken: "Bring your notebook, a pen, and a little curiosity.", units: ["Bring your notebook", "a pen", "and a little curiosity."], pauseAt: [0.36, 0.57])
        ],
        .energy: [
            VoiceExercise(id: "steady", title: "Keep the same energy", instruction: "Say a relaxed “ah” and keep its strength steady. Stay at a comfortable volume.", prompt: "ah ———"),
            VoiceExercise(id: "build", title: "Soft to strong", instruction: "Start “ah” softly, then gradually give it more energy. Stop well before strain.", prompt: "softer → normal → stronger", pattern: .rise),
            VoiceExercise(id: "soften", title: "Strong to soft", instruction: "Begin with comfortable energy, then gently soften “ah”. Keep the sound going.", prompt: "stronger → normal → softer", pattern: .fall),
            VoiceExercise(id: "swell", title: "Grow, then soften", instruction: "Let the sound grow stronger in the middle, then soften it again.", prompt: "softer → stronger → softer", pattern: .arch, duration: 4),
            VoiceExercise(id: "word", title: "Give one word more energy", instruction: "Give REALLY a little more strength. Keep the rest of the phrase softer.", prompt: "I REALLY mean it.", duration: 2.5, spoken: "I really mean it.", units: ["I", "REALLY", "mean", "it"], strong: [1])
        ],
        .articulation: [
            VoiceExercise(id: "pa-ta-ka", title: "Three clear movements", instruction: "Say pa – ta – ka slowly. Make each mouth movement deliberate and relaxed.", prompt: "pa – ta – ka", spoken: "pah, tah, kah.", units: ["pa", "ta", "ka"], rate: 0.33, review: "Can you hear three distinct, clear syllables?"),
            VoiceExercise(id: "ba-da-ga", title: "Keep the sounds distinct", instruction: "Say ba – da – ga. Listen for a clear start to every syllable.", prompt: "ba – da – ga", spoken: "bah, dah, gah.", units: ["ba", "da", "ga"], rate: 0.33, review: "Does each syllable have a clear beginning?"),
            VoiceExercise(id: "vowels", title: "Give vowels some space", instruction: "Move slowly between ee – ah – oo. Let your mouth change shape for each sound.", prompt: "ee – ah – oo", spoken: "ee, ah, oo.", units: ["ee", "ah", "oo"], rate: 0.33, review: "Do the three vowels sound different from each other?"),
            VoiceExercise(id: "consonants", title: "Finish the words clearly", instruction: "Say each short word carefully. Let the final consonant be audible without forcing it.", prompt: "map · mat · back", spoken: "map, mat, back.", units: ["map", "mat", "back"], rate: 0.36, review: "Can you hear the ending of each word?"),
            VoiceExercise(id: "normal-speed", title: "Clear at a natural speed", instruction: "Start slowly, then repeat at normal speed. Keep the sounds clear as you speed up.", prompt: "Red leather, yellow leather.", spoken: "Red leather, yellow leather.", contrast: "Red leather, yellow leather.", contrastLabel: "Hear it slowly", units: ["Red", "leather", "yellow", "leather"], review: "Are the words still clear at your normal speed?")
        ],
        .connected: [
            VoiceExercise(id: "link", title: "Join the words", instruction: "Listen slowly, then at normal speed. Let the end of “turn” flow into “it”.", prompt: "turn‿it‿on", spoken: "Turn it on.", contrast: "Turn it on.", contrastLabel: "Hear it slowly", units: ["turn", "it", "on"], review: "Do the words flow together without a gap?"),
            VoiceExercise(id: "reduction", title: "Hear a shorter form", instruction: "Compare “want to” with the casual “wanna”. Try the shorter version after listening.", prompt: "want to → wanna", spoken: "I wanna go.", contrast: "I want to go.", contrastLabel: "Hear the full form", units: ["want to", "wanna"], review: "Can you hear “wanna” as one connected movement?"),
            VoiceExercise(id: "weak-forms", title: "Keep the small words light", instruction: "Listen for the light “of” in “a cup of tea”. Let it connect to the words around it.", prompt: "a cup‿of tea", spoken: "A cup of tea.", contrast: "A cup of tea.", contrastLabel: "Hear it slowly", units: ["a", "cup", "of", "tea"], strong: [1, 3], review: "Is “of” light and connected, while “cup” and “tea” stay clear?"),
            VoiceExercise(id: "contraction", title: "Two words become one", instruction: "Compare “I am” and “I’m”. Try the contraction in the whole phrase.", prompt: "I am ready → I’m ready", spoken: "I'm ready.", contrast: "I am ready.", contrastLabel: "Hear the full form", units: ["I’m", "ready"], review: "Does “I’m” sound like one smooth syllable?"),
            VoiceExercise(id: "lighter-sound", title: "Let a sound become lighter", instruction: "Let “next day” flow together. In everyday speech, the t can become very light or disappear; don’t force it.", prompt: "nex(t)‿day", spoken: "Next day.", contrast: "Next day.", contrastLabel: "Hear it slowly", units: ["next", "day"], review: "Does the phrase flow, with “day” clear and no extra syllable between the words?"),
            VoiceExercise(id: "phrase", title: "Connect a whole question", instruction: "Hear the slow version, then the normal version. Imitate the flow between words.", prompt: "What‿are‿you doing?", spoken: "What are you doing?", contrast: "What are you doing?", contrastLabel: "Hear it slowly", units: ["What", "are", "you", "doing?"], review: "Do the first three words flow together naturally?")
        ]
    ]
}
