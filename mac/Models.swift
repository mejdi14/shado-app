import Foundation

struct Mark: Codable { let word: String; let match: Bool }
struct Curves: Codable { let original: [Double]; let you: [Double] }
struct TakeResult: Codable {
    let id: String; let audio: String; let accuracy: Int; let rhythm: Int; let intonation: Int?
    let words: [Mark]; let curves: Curves; let tips: [String]; let playbackSpeed: Double?
}
struct Phrase: Codable { var start: Double; var end: Double; var text: String; var practised: Bool?; var latest: TakeResult?; var takes: Int? }
struct Lesson: Codable { let id: String; var title: String; let source: String; let duration: Double; var phrases: [Phrase]; let sample: Bool? }
struct LibraryItem: Codable, Identifiable { let id: String; let title: String; let source: String; let duration: Double; let sample: Bool; let count: Int; let practised: Int }
struct JobStart: Codable { let jobId: String }
struct Job: Codable { let state: String; let message: String?; let lessonId: String? }
struct Busy { var title: String; var message: String }

func fmt(_ n: Double) -> String { String(format: "%02d:%02d", Int(n) / 60, Int(n) % 60) }
