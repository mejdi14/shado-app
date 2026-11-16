import SwiftUI
import UniformTypeIdentifiers

extension Color {
    static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color { Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }) }
    static let canvas = adaptive(NSColor(white: 0.985, alpha: 1), NSColor(white: 0.065, alpha: 1))
    static let surface = adaptive(.white, NSColor(white: 0.11, alpha: 1))
    static let side = adaptive(NSColor(white: 0.96, alpha: 1), NSColor(white: 0.085, alpha: 1))
    static let line = adaptive(NSColor(white: 0, alpha: 0.085), NSColor(white: 1, alpha: 0.09))
    static let subtle = adaptive(NSColor(white: 0, alpha: 0.045), NSColor(white: 1, alpha: 0.06))
    static let selected = adaptive(NSColor(white: 0, alpha: 0.075), NSColor(white: 1, alpha: 0.11))
    static let ink = adaptive(NSColor(white: 0.06, alpha: 1), NSColor(white: 0.97, alpha: 1))
    static let inkInverse = adaptive(.white, NSColor(white: 0.06, alpha: 1))
    static let good = Color(red: 0.09, green: 0.6, blue: 0.4)
    static let warn = Color(red: 0.92, green: 0.47, blue: 0.13)
    static let rec = Color(red: 0.94, green: 0.25, blue: 0.27)
    static let violet = Color(red: 0.45, green: 0.36, blue: 0.98)
    static let rose = Color(red: 0.94, green: 0.38, blue: 0.6)
    static let pitch = Color(red: 0.2, green: 0.56, blue: 1)
}

extension View {
    func panel(_ r: CGFloat = 14) -> some View { background(RoundedRectangle(cornerRadius: r).fill(Color.surface)).overlay(RoundedRectangle(cornerRadius: r).stroke(Color.line)) }
}

func muted(_ s: String) -> some View { Text(s).font(.system(size: 12)).foregroundStyle(.secondary) }
func legendDot(_ c: Color, _ t: String) -> some View { HStack(spacing: 6) { Circle().fill(c).frame(width: 7, height: 7); muted(t) } }
func sourceLabel(_ source: String, _ sample: Bool) -> String { sample ? "Guided sample · built-in Mac voice" : source.hasPrefix("http") ? "YouTube" : source.hasPrefix("PDF") ? source : "Your file" }
func speedLabel(_ v: Double) -> String { v == 1 ? "1×" : String(format: "%g×", v) }

// MARK: Building blocks

struct Orb: View {
    let seed: String
    var size: CGFloat = 32
    static let palettes: [[Color]] = [
        [Color(red: 0.98, green: 0.55, blue: 0.35), Color(red: 0.94, green: 0.33, blue: 0.6), Color(red: 0.99, green: 0.8, blue: 0.45)],
        [Color(red: 0.3, green: 0.55, blue: 0.98), Color(red: 0.45, green: 0.85, blue: 0.95), Color(red: 0.55, green: 0.4, blue: 0.98)],
        [Color(red: 0.55, green: 0.36, blue: 0.98), Color(red: 0.94, green: 0.45, blue: 0.85), Color(red: 0.4, green: 0.6, blue: 1)],
        [Color(red: 0.2, green: 0.75, blue: 0.6), Color(red: 0.6, green: 0.9, blue: 0.5), Color(red: 0.25, green: 0.6, blue: 0.9)],
        [Color(red: 0.99, green: 0.75, blue: 0.3), Color(red: 0.98, green: 0.45, blue: 0.35), Color(red: 0.95, green: 0.85, blue: 0.6)],
    ]
    var body: some View {
        let n = seed.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xfffff }
        let c = Orb.palettes[n % Orb.palettes.count]
        Circle().fill(AngularGradient(gradient: Gradient(colors: c + [c[0]]), center: .center, angle: .degrees(Double(n % 360))))
            .overlay(Circle().fill(RadialGradient(gradient: Gradient(colors: [.white.opacity(0.6), .white.opacity(0)]), center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: size * 0.6)))
            .overlay(Circle().stroke(Color.black.opacity(0.06)))
            .frame(width: size, height: size)
    }
}

struct Bar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.subtle)
                Capsule().fill(LinearGradient(gradient: Gradient(colors: [.violet, .rose]), startPoint: .leading, endPoint: .trailing)).frame(width: g.size.width * max(0, min(1, value)))
            }
        }
    }
}

struct PillStyle: ButtonStyle {
    var primary = false
    var compact = false
    func makeBody(configuration c: Configuration) -> some View { Styled(c: c, primary: primary, compact: compact) }
    struct Styled: View {
        let c: ButtonStyleConfiguration; let primary: Bool; let compact: Bool
        @Environment(\.isEnabled) var enabled
        @State var hover = false
        var body: some View {
            c.label.font(.system(size: compact ? 12 : 13, weight: .medium))
                .padding(.horizontal, compact ? 11 : 15).padding(.vertical, compact ? 6 : 8)
                .foregroundStyle(primary ? Color.inkInverse : Color.ink)
                .background(Capsule().fill(primary ? Color.ink.opacity(hover ? 0.85 : 1) : hover ? Color.subtle : Color.surface))
                .overlay(Capsule().stroke(primary ? Color.clear : Color.line))
                .opacity(enabled ? (c.isPressed ? 0.7 : 1) : 0.4)
                .contentShape(Capsule()).onHover { hover = $0 && enabled }
        }
    }
}

struct RoundStyle: ButtonStyle {
    var size: CGFloat = 30
    var fill: Color = .surface
    var fg: Color = .ink
    var border = true
    func makeBody(configuration c: Configuration) -> some View { Styled(c: c, style: self) }
    struct Styled: View {
        let c: ButtonStyleConfiguration; let style: RoundStyle
        @Environment(\.isEnabled) var enabled
        @State var hover = false
        var body: some View {
            c.label.font(.system(size: style.size * 0.36, weight: .semibold)).foregroundStyle(style.fg)
                .frame(width: style.size, height: style.size)
                .background(Circle().fill(style.fill)).overlay(Circle().fill(Color.primary.opacity(hover ? 0.06 : 0)))
                .overlay(Circle().stroke(style.border ? Color.line : .clear))
                .opacity(enabled ? (c.isPressed ? 0.7 : 1) : 0.35)
                .contentShape(Circle()).onHover { hover = $0 && enabled }
        }
    }
}

struct RowStyle: ButtonStyle {
    var active = false
    var pad: CGFloat = 6
    func makeBody(configuration c: Configuration) -> some View { Styled(c: c, active: active, pad: pad) }
    struct Styled: View {
        let c: ButtonStyleConfiguration; let active: Bool; let pad: CGFloat
        @Environment(\.isEnabled) var enabled
        @State var hover = false
        var body: some View {
            c.label.padding(.horizontal, 8).padding(.vertical, pad).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(active ? Color.selected : hover ? Color.subtle : .clear))
                .contentShape(Rectangle()).onHover { hover = $0 && enabled }.opacity(enabled || active ? 1 : 0.55)
        }
    }
}

struct TileStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View { Styled(c: c) }
    struct Styled: View {
        let c: ButtonStyleConfiguration
        @Environment(\.isEnabled) var enabled
        @State var hover = false
        var body: some View {
            c.label.background(RoundedRectangle(cornerRadius: 14).fill(Color.surface))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(hover ? Color.ink.opacity(0.25) : Color.line))
                .opacity(enabled ? (c.isPressed ? 0.75 : 1) : 0.45)
                .contentShape(Rectangle()).onHover { hover = $0 && enabled }
        }
    }
}

struct Segmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let on = selection == options[i].0
                Button { selection = options[i].0 } label: {
                    Text(options[i].1).font(.system(size: 12.5, weight: .medium)).foregroundStyle(on ? Color.ink : Color.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity)
                        .background(Capsule().fill(on ? Color.surface : .clear).shadow(color: .black.opacity(on ? 0.1 : 0), radius: 2, y: 1))
                        .contentShape(Capsule())
                }.buttonStyle(.plain)
            }
        }.padding(3).background(Capsule().fill(Color.subtle))
    }
}

struct Pulse: View {
    @State var on = false
    var body: some View {
        Circle().stroke(Color.rec.opacity(0.6), lineWidth: 2).scaleEffect(on ? 1.5 : 1).opacity(on ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { on = true } }
    }
}

struct StepCard<Content: View>: View {
    let n: Int
    let title: String
    let detail: String
    var active = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(n)").font(.system(size: 11, weight: .semibold)).frame(width: 20, height: 20)
                    .background(Circle().fill(active ? Color.ink : Color.subtle)).foregroundStyle(active ? Color.inkInverse : Color.secondary)
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            content
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(active ? Color.ink.opacity(0.35) : Color.line))
    }
}

// MARK: Shell

struct Sidebar: View {
    @EnvironmentObject var s: Store
    @EnvironmentObject var training: VoiceTrainingStore
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) { Orb(seed: "shadow studio", size: 22); Text("Shadow Studio").font(.system(size: 15, weight: .semibold)).tracking(-0.2) }.padding(.horizontal, 8).padding(.bottom, 18)
            Button { s.stopPlayback(); training.stopPlayback(); s.showImport = true } label: { Label("New session", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(PillStyle(primary: true)).disabled(s.locked).padding(.bottom, 16)
            nav("Home", "square.grid.2x2", active: s.showLibrary && !s.showTraining) { Task { await s.openLibrary() } }
            if (s.showLibrary || s.showTraining), let lesson = s.lesson, s.phrase != nil {
                let language = lesson.language == "fr" ? "French" : "English"
                nav("Continue", "waveform", active: false, subtitle: lesson.title,
                    detail: "\(language) · Phrase \(s.index + 1) of \(lesson.phrases.count)") {
                    Task { await s.openLesson(lesson.id) }
                }
            } else {
                nav("Practice", "waveform", active: !s.showLibrary && !s.showTraining) { s.showTraining = false; s.showLibrary = false }
            }
            nav("Voice Training", "waveform.path", active: s.showTraining) { s.stopPlayback(); s.showTraining = true }
            if !s.library.isEmpty {
                Text("Sessions").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.top, 20).padding(.bottom, 4)
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(s.library) { l in
                            Button { Task { await s.openLesson(l.id) } } label: { HStack(spacing: 9) { Orb(seed: l.id, size: 16); Text(l.title).lineLimit(1); Spacer(minLength: 0) } }
                                .buttonStyle(RowStyle(active: !s.showLibrary && !s.showTraining && s.lesson?.id == l.id)).disabled(s.locked)
                        }
                    }
                }
            }
            Spacer(minLength: 12)
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) { Text("Private by design").font(.system(size: 12, weight: .medium)); Text("Audio and recordings stay on this Mac.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.padding(11).frame(maxWidth: .infinity, alignment: .leading).panel(10)
        }
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 14).frame(maxHeight: .infinity, alignment: .top)
        .background(Color.side.ignoresSafeArea())
    }
    func nav(_ title: String, _ icon: String, active: Bool, subtitle: String? = nil, detail: String? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: icon).frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(active ? .medium : .regular)
                    if let subtitle { muted(subtitle).lineLimit(1) }
                    if let detail { muted(detail).monospacedDigit() }
                }
                Spacer(minLength: 0)
            }.accessibilityElement(children: .combine)
        }.buttonStyle(RowStyle(active: active, pad: 7)).disabled(s.locked)
    }
}

struct BusyOverlay: View {
    let busy: Busy
    var body: some View {
        ZStack {
            Color.canvas.opacity(0.6).ignoresSafeArea()
            HStack(spacing: 16) {
                ZStack { Orb(seed: busy.title, size: 40); ProgressView().controlSize(.small) }
                VStack(alignment: .leading, spacing: 3) { Text(busy.title).font(.system(size: 14, weight: .semibold)); Text(busy.message).font(.system(size: 12.5)).foregroundStyle(.secondary).frame(maxWidth: 340, alignment: .leading) }
            }.padding(22).panel(18).shadow(color: .black.opacity(0.08), radius: 24, y: 8)
        }
    }
}

struct ToastView: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.inkInverse).padding(.horizontal, 16).padding(.vertical, 10)
            .background(Capsule().fill(Color.ink)).shadow(color: .black.opacity(0.15), radius: 12, y: 4).frame(maxWidth: 560)
    }
}

private let missingSampleHint = "The guided sample is unavailable. Restart the local engine on this Mac to try again, or add your own clip."

// MARK: Home

struct LibraryView: View {
    @EnvironmentObject var s: Store
    @State private var query = ""
    @State private var language = "all"
    @State private var progress = "all"
    @State private var order = "newest"

    private var visibleSessions: [LibraryItem] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = s.library.filter { item in
            let itemLanguage = item.language == "fr" ? "fr" : "en"
            let status = item.practised == 0 ? "new" : item.practised >= item.count && item.count > 0 ? "complete" : "started"
            return (search.isEmpty || item.title.localizedCaseInsensitiveContains(search))
                && (language == "all" || language == itemLanguage)
                && (progress == "all" || progress == status)
        }
        switch order {
        case "title":
            return matches.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case "progress":
            return matches.sorted {
                Double($0.practised) / Double(max(1, $0.count)) > Double($1.practised) / Double(max(1, $1.count))
            }
        default:
            return matches
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search titles", text: $query)
            HStack(spacing: 14) {
                Picker("Language", selection: $language) {
                    Text("All languages").tag("all")
                    Text("English").tag("en")
                    Text("French").tag("fr")
                }
                Picker("Progress", selection: $progress) {
                    Text("All progress").tag("all")
                    Text("Not started").tag("new")
                    Text("In progress").tag("started")
                    Text("Completed").tag("complete")
                }
                Picker("Sort by", selection: $order) {
                    Text("Newest added").tag("newest")
                    Text("Title A–Z").tag("title")
                    Text("Most complete").tag("progress")
                }
                Button("Reset") {
                    query = ""
                    language = "all"
                    progress = "all"
                    order = "newest"
                }.disabled(query.isEmpty && language == "all" && progress == "all" && order == "newest")
            }.pickerStyle(.menu)
        }.padding(.horizontal, 18).padding(.bottom, 14)
    }

    var body: some View {
        let sessions = visibleSessions
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Home").font(.system(size: 28, weight: .semibold)).tracking(-0.6)
                Text("Pick up a session, or bring in a new voice to practise with.").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    if let id = s.sampleId {
                        tile("Try the guided sample", "Practise with a built-in Mac voice", "sparkles", "sample") { Task { await s.openLesson(id) } }
                    }
                    tile("Import from YouTube", "Paste a link to a video", "play.fill", "youtube") { s.importUpload = false; s.showImport = true }
                    tile("Upload a file", "Audio, video or a PDF from your Mac", "arrow.up", "upload") { s.importUpload = true; s.showImport = true }
                }.disabled(s.locked)
                if s.sampleId == nil && !s.locked { muted(missingSampleHint) }
            }
            VStack(spacing: 0) {
                HStack { Text("Sessions").font(.system(size: 15, weight: .semibold)); Spacer(); muted("\(sessions.count)") }.padding(.horizontal, 18).padding(.vertical, 14)
                if !s.library.isEmpty { controls }
                Rectangle().fill(Color.line).frame(height: 1)
                if s.library.isEmpty { muted("No sessions yet. Import a clip to create your first one.").frame(maxWidth: .infinity).padding(32) }
                else if sessions.isEmpty { muted("No sessions match. Change your search or filters, or choose Reset.").frame(maxWidth: .infinity).padding(32) }
                VStack(spacing: 2) {
                    ForEach(sessions) { l in
                        Button { Task { await s.openLesson(l.id) } } label: {
                            HStack(spacing: 14) {
                                Orb(seed: l.id, size: 32)
                                VStack(alignment: .leading, spacing: 2) { Text(l.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1).foregroundStyle(Color.ink); muted("\(l.language == "fr" ? "French" : "English") · \(sourceLabel(l.source, l.sample))") }
                                Spacer(minLength: 12)
                                muted("\(l.count) phrases").frame(width: 84, alignment: .leading)
                                muted(fmt(l.duration)).monospacedDigit().frame(width: 52, alignment: .leading)
                                HStack(spacing: 8) { Bar(value: Double(l.practised) / Double(max(1, l.count))).frame(width: 72, height: 4); muted("\(l.practised)/\(l.count)").monospacedDigit() }.frame(width: 128, alignment: .leading)
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                            }
                        }.buttonStyle(RowStyle(pad: 9)).disabled(s.locked)
                    }
                }.padding(6)
            }.panel(16)
        }.padding(36).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity)
    }
    func tile(_ title: String, _ detail: String, _ icon: String, _ seed: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack { Orb(seed: seed, size: 38); Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(.white) }
                VStack(alignment: .leading, spacing: 2) { Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color.ink); muted(detail) }
                Spacer(minLength: 0)
            }.padding(14).frame(maxWidth: .infinity)
        }.buttonStyle(TileStyle())
    }
}

// MARK: Practice

struct StudioView: View {
    @EnvironmentObject var s: Store
    @State private var showInspector = true
    var body: some View {
        if let l = s.lesson, let p = s.phrase {
            HStack(spacing: 0) {
                ScrollView { PracticePanel(lesson: l, phrase: p, showInspector: $showInspector).padding(32).frame(maxWidth: 880).frame(maxWidth: .infinity) }
                if showInspector {
                    Rectangle().fill(Color.line).frame(width: 1).ignoresSafeArea()
                    Inspector(lesson: l).frame(width: 330)
                }
            }
        } else if let l = s.lesson {
            VStack(spacing: 14) {
                Orb(seed: l.id, size: 56)
                Text(l.title).font(.system(size: 22, weight: .semibold))
                Text("This session has no phrases to practise.").foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    if l.sample != true {
                        Button("Re-split phrases…") { s.showResplit = true }.buttonStyle(PillStyle())
                    }
                    Button("Delete session…", role: .destructive) { s.showDelete = true }.buttonStyle(PillStyle())
                }.disabled(s.locked)
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView { EmptyStudio() }
        }
    }
}

struct EmptyStudio: View {
    @EnvironmentObject var s: Store
    var body: some View {
        VStack(spacing: 22) {
            Orb(seed: "welcome", size: 84)
            VStack(spacing: 10) {
                Text("Practise English or French,\none phrase at a time.").font(.system(size: 28, weight: .semibold)).tracking(-0.6).multilineTextAlignment(.center)
                if s.sampleId != nil {
                    Text("Start with a short example spoken by a built-in Mac voice.").foregroundStyle(.secondary)
                } else if !s.locked {
                    Text(missingSampleHint).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 470)
                }
            }
            HStack(spacing: 10) {
                if let id = s.sampleId {
                    Button("Try the guided sample") { Task { await s.openLesson(id) } }.buttonStyle(PillStyle(primary: true))
                }
                Button { s.importUpload = false; s.showImport = true } label: { Label("Add a voice", systemImage: "plus") }
                    .buttonStyle(PillStyle(primary: s.sampleId == nil))
            }.disabled(s.locked)
            HStack(alignment: .top, spacing: 12) {
                how(1, "Import", "A YouTube link, an audio or video file, or a PDF.")
                how(2, "Practise", "Listen to a phrase, then record yourself.")
                how(3, "Compare", "Check your words, rhythm and pitch.")
            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: 640).padding(.top, 18)
        }.padding(48).frame(maxWidth: .infinity, minHeight: 600)
    }
    func how(_ n: Int, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(n)").font(.system(size: 11, weight: .semibold)).frame(width: 20, height: 20).background(Circle().fill(Color.subtle))
            Text(title).font(.system(size: 13.5, weight: .semibold))
            muted(detail).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).panel(14)
    }
}

struct PracticePanel: View {
    @State private var showTakeHistory = false
    @EnvironmentObject var s: Store
    let lesson: Lesson
    let phrase: Phrase
    @Binding var showInspector: Bool
    static let hiddenWidths: [CGFloat] = [70, 44, 92, 58, 76]
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Orb(seed: lesson.id, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lesson.title).font(.system(size: 20, weight: .semibold)).tracking(-0.3).lineLimit(1)
                    muted("\(lesson.phrases.count) phrases · \(fmt(lesson.duration)) · \(sourceLabel(lesson.source, lesson.sample == true))")
                }
                Spacer()
                Button { showInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                    .buttonStyle(RoundStyle()).help(showInspector ? "Hide phrases and feedback" : "Show phrases and feedback")
                    .accessibilityLabel(showInspector ? "Hide phrases and feedback" : "Show phrases and feedback")
                Menu {
                    Button("Edit this phrase…") { s.stopPlayback(); s.showEdit = true }
                    if lesson.sample != true { Button("Re-split phrases…") { s.stopPlayback(); s.showResplit = true } }
                    Divider()
                    Button("Delete session…", role: .destructive) { s.stopPlayback(); s.showDelete = true }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(s.locked).help("More")
            }
            VStack(alignment: .leading, spacing: 8) {
                Segmented(options: Mode.allCases.map { ($0, $0.title) }, selection: Binding(get: { s.mode }, set: { s.setMode($0) })).frame(maxWidth: 340).disabled(s.locked)
                muted(s.mode.hint)
            }
            phraseCard
            muted("Space  play / pause   ·   R  record   ·   ← →  change phrase").frame(maxWidth: .infinity)
        }
    }

    var phraseCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Button { s.select(s.index - 1) } label: { Image(systemName: "chevron.left") }.buttonStyle(RoundStyle(size: 28)).keyboardShortcut(.leftArrow, modifiers: []).disabled(s.locked || s.index == 0).help("Previous phrase (←)")
                Text("Phrase \(s.index + 1) of \(lesson.phrases.count)").font(.system(size: 13, weight: .medium)).monospacedDigit()
                Button { s.select(s.index + 1) } label: { Image(systemName: "chevron.right") }.buttonStyle(RoundStyle(size: 28)).keyboardShortcut(.rightArrow, modifiers: []).disabled(s.locked || s.index >= lesson.phrases.count - 1).help("Next phrase (→)")
                Spacer()
                muted("\(fmt(phrase.start)) – \(fmt(phrase.end))").monospacedDigit()
                Button { s.concealed.toggle() } label: { Image(systemName: s.concealed ? "eye" : "eye.slash") }.buttonStyle(RoundStyle(size: 28)).disabled(s.locked).help(s.concealed ? "Show text" : "Hide text")
                Button { s.stopPlayback(); s.showEdit = true } label: { Image(systemName: "pencil") }.buttonStyle(RoundStyle(size: 28)).disabled(s.locked).help("Edit this phrase")
            }
            if s.concealed {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) { ForEach(PracticePanel.hiddenWidths.indices, id: \.self) { i in Capsule().fill(Color.subtle).frame(width: PracticePanel.hiddenWidths[i], height: 18) } }
                    Button("Show text") { s.concealed = false }.buttonStyle(PillStyle(compact: true))
                }.frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            } else {
                PracticeSentence(phrase: phrase)
            }
            if phrase.latest == nil && !s.recording {
                muted("Listen for the speaker’s pauses and emphasis.")
            }
            controls
            if let problem = s.microphoneProblem { MicrophoneRecoveryView(problem: problem) }
            if s.lesson?.language != "fr" { MouthGuide(phrase: phrase) }
            if phrase.latest != nil {
                VStack(alignment: .leading, spacing: 8) {
                    muted("Replay your take and compare its rhythm with the original.")
                    comparison
                }
            }
            Button { s.stopPlayback(); showTakeHistory = true } label: {
                Label("Take history", systemImage: "clock.arrow.circlepath")
            }.buttonStyle(PillStyle(compact: true)).disabled(s.locked)
            Rectangle().fill(Color.line).frame(height: 1)
            if phrase.latest != nil { NextStepView(phrase: phrase) }
            else { deliveryGuide }
            VoiceMapView(phrase: phrase)
        }.padding(24).panel(16)
            .sheet(isPresented: $showTakeHistory, onDismiss: { s.stopPlayback() }) {
                TakeHistorySheet().environmentObject(s)
            }
    }

    var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { playbackButtons; Spacer(minLength: 8); recordButton }
                VStack(alignment: .leading, spacing: 12) { HStack(spacing: 12) { playbackButtons }; recordButton }
            }
            if phrase.latest == nil && !s.recording && s.microphoneProblem == nil {
                muted("Use the microphone to record yourself saying the phrase.")
            }
            TimelineView(.animation(minimumInterval: 0.1, paused: !s.isPlaying)) { _ in
                let head = s.isPlaying ? min(max(0, (s.original?.currentTime ?? phrase.start) - phrase.start), phrase.end - phrase.start) : s.position
                HStack(spacing: 10) {
                    Slider(value: Binding(get: { head }, set: { s.seek($0) }), in: 0...max(0.01, phrase.end - phrase.start))
                        .controlSize(.small).disabled(s.locked || s.isTakePlaying).accessibilityLabel("Position in example")
                    Text("\(fmt(head)) / \(fmt(phrase.end - phrase.start))").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder var playbackButtons: some View {
        Button { s.togglePlay() } label: { Label(s.isPlaying ? "Pause" : "Listen", systemImage: s.isPlaying ? "pause.fill" : "play.fill") }
            .buttonStyle(PillStyle(primary: phrase.latest == nil)).keyboardShortcut(.space, modifiers: []).disabled(s.locked).help("Play the example (Space)")
        Menu { ForEach(PracticeDefaults.speeds, id: \.self) { v in Button(speedLabel(v)) { s.speed = v } } } label: { Text(speedLabel(s.speed)) }
            .menuStyle(.borderlessButton).fixedSize().disabled(s.locked).help("Playback speed")
        Button { s.looping.toggle() } label: { Image(systemName: "repeat") }
            .buttonStyle(RoundStyle(size: 30, fill: s.looping ? .selected : .surface)).disabled(s.locked)
            .help(s.looping ? "Repeat is on" : "Repeat this phrase").accessibilityLabel(s.looping ? "Turn repeat off" : "Turn repeat on")
    }

    var recordButton: some View {
        HStack(spacing: 8) {
            if s.starting || s.stopping { ProgressView().controlSize(.small) }
            Button { Task { await s.toggleRecording() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: s.recording ? "stop.fill" : "mic.fill").foregroundStyle(Color.rec)
                    Text(s.recording ? "Stop · \(fmt(s.recordSeconds))" : s.microphoneProblem != nil ? "Retry recording" : phrase.latest == nil ? "Record" : "Try again").monospacedDigit()
                }
            }.buttonStyle(PillStyle(primary: phrase.latest != nil || s.recording)).keyboardShortcut("r", modifiers: [])
                .disabled(s.starting || s.stopping || s.busy != nil).help(s.recording ? "Stop recording (R)" : "Record a take (R)")
        }
    }

    var comparison: some View {
        HStack(spacing: 8) {
            Button { Task { await s.toggleTake() } } label: { Label(s.isTakePlaying ? "Stop take" : "Your take", systemImage: s.isTakePlaying ? "stop.fill" : "play.fill") }.buttonStyle(PillStyle(compact: true))
            Button { s.compareAB() } label: { Label("Original → you", systemImage: "arrow.left.arrow.right") }.buttonStyle(PillStyle(compact: true)).help("Play the original, then your take")
            Spacer(minLength: 0)
        }.disabled(s.locked)
    }

    var deliveryGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Listen for the delivery", systemImage: "ear").font(.system(size: 12, weight: .semibold))
            if let v = s.voice, speechSpan(v.src) != nil {
                Text(v.pauses.isEmpty ? "Keep the words flowing. Listen to how the quieter words fit between the louder ones." : s.concealed || (phrase.words ?? []).isEmpty ? "Listen for where the speaker pauses, then repeat those phrase groups." : "Follow the phrase groups. Leave a little space at each pause marker.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Listen once, then repeat the timing and the way the words join together.").font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PracticeSentence: View {
    @EnvironmentObject var s: Store
    let phrase: Phrase
    static let tokenPattern = try! NSRegularExpression(pattern: "\\p{L}[\\p{L}\\p{M}]*(?:[\'’]\\p{L}[\\p{L}\\p{M}]*)*")
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: !s.isPlaying)) { _ in
            let head = s.isPlaying ? (s.original?.currentTime ?? phrase.start) - phrase.start : nil
            VStack(alignment: .leading, spacing: 14) {
                Text(sentence(head)).font(.system(size: 27)).tracking(-0.3).lineSpacing(7).textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { annotationKey }
                    VStack(alignment: .leading, spacing: 6) { annotationKey }
                }
            }.padding(.vertical, 12)
        }
    }

    @ViewBuilder var annotationKey: some View {
        if let v = s.voice, !(phrase.words ?? []).isEmpty {
            Text("Bold = louder in example").font(.system(size: 11)).foregroundStyle(.secondary)
            if !v.pauses.isEmpty { Text("| = pause").font(.system(size: 11)).foregroundStyle(.secondary) }
        }
        if phrase.latest?.words.contains(where: { !$0.match }) == true {
            Text("Underline = check word").font(.system(size: 11)).foregroundStyle(Color.warn)
        }
        if !ending(s.voice?.src ?? []).isEmpty {
            Text("Arrow = voice ending").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    static func timedTokens(_ phrase: Phrase) -> [(Int, Word)] {
        let ns = phrase.text as NSString, re = tokenPattern
        let matches = re.matches(in: phrase.text, range: NSRange(location: 0, length: ns.length))
        let timed = (phrase.words ?? []).enumerated().flatMap { i, w in
            re.matches(in: w.word, range: NSRange(location: 0, length: (w.word as NSString).length)).map { (i, w, (w.word as NSString).substring(with: $0.range)) }
        }
        guard matches.count == timed.count, zip(matches, timed).allSatisfy({ a, b in
            ns.substring(with: a.range).replacingOccurrences(of: "’", with: "'").lowercased() == b.2.replacingOccurrences(of: "’", with: "'").lowercased()
        }) else { return [] }
        return timed.map { ($0.0, $0.1) }
    }

    func sentence(_ head: Double?) -> AttributedString {
        let ns = phrase.text as NSString, re = Self.tokenPattern
        let matches = re.matches(in: phrase.text, range: NSRange(location: 0, length: ns.length))
        let words = phrase.words ?? [], timed = Self.timedTokens(phrase)
        let aligned = matches.count == timed.count
        let pauseAfter = Set((s.voice?.pauses ?? []).compactMap { a, b -> Int? in
            let mid = (a + b) / 2
            guard let i = words.lastIndex(where: { $0.end - phrase.start <= mid }), i + 1 < words.count,
                  words[i + 1].start - phrase.start >= mid else { return nil }
            return i
        })
        var out = AttributedString(), last = 0
        for (i, m) in matches.enumerated() {
            out += AttributedString(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            if aligned, i > 0, timed[i - 1].0 != timed[i].0, pauseAfter.contains(timed[i - 1].0) {
                var pause = AttributedString("| "); pause.foregroundColor = .warn; out += pause
            }
            var word = AttributedString(ns.substring(with: m.range))
            if aligned {
                let (wi, wd) = timed[i]
                if s.voice?.stress.contains(wi) == true { word.font = .system(size: 27, weight: .semibold) }
                if let head, head >= wd.start - phrase.start, head < wd.end - phrase.start { word.backgroundColor = .pitch.opacity(0.22) }
            }
            if let marks = phrase.latest?.words, i < marks.count, !marks[i].match { word.foregroundColor = .warn; word.underlineStyle = .single }
            out += word; last = m.range.location + m.range.length
        }
        out += AttributedString(ns.substring(from: last))
        let end = ending(s.voice?.src ?? [])
        if !end.isEmpty {
            var arrow = AttributedString(end.hasPrefix("goes up") ? " ↗" : end.hasPrefix("goes down") ? " ↘" : " →")
            arrow.foregroundColor = .pitch; out += arrow
        }
        return out
    }
}

struct NextStepView: View {
    @EnvironmentObject var s: Store
    let phrase: Phrase
    var body: some View {
        let next = cue
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.up.right").foregroundStyle(Color.violet)
                Text("Try this next").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("Take \(phrase.takes ?? 1)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(next.title).font(.system(size: 15, weight: .semibold))
            Text(next.detail).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button { s.playOriginal(once: true, rate: phrase.latest?.playbackSpeed ?? 1, excerpt: next.excerpt) } label: {
                Label(next.excerpt == nil ? "Replay example" : "Hear this part", systemImage: "play.fill")
            }.buttonStyle(PillStyle(compact: true)).disabled(s.locked)
            muted("Practice suggestion · compare by listening").font(.system(size: 11))
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(Color.violet.opacity(0.08)))
    }

    var cue: (title: String, detail: String, excerpt: ClosedRange<Double>?) {
        let r = phrase.latest, len = max(0.01, phrase.end - phrase.start)
        if let marks = r?.words, let i = marks.firstIndex(where: { !$0.match }) {
            let timed = PracticeSentence.timedTokens(phrase)
            var excerpt: ClosedRange<Double>? = nil
            if i < timed.count {
                let a = max(0, timed[max(0, i - 1)].1.start - phrase.start - 0.12)
                let b = min(len, timed[min(timed.count - 1, i + 1)].1.end - phrase.start + 0.15)
                if b > a { excerpt = a...b }
            }
            let detail = s.concealed ? "A word wasn’t recognised in your take. Listen to this part, then repeat it with the surrounding words. Recognition can make mistakes." : "Speech recognition didn’t match “\(marks[i].word)”. Listen to it with the surrounding words, then try again. Recognition can make mistakes."
            return ("Check one word in context", detail, excerpt)
        }
        if let ratio = r?.durationRatio, ratio > 1.15 {
            return ("Keep the pace moving", "Your take was about \(Int(((ratio - 1) * 100).rounded()))% longer than the example at the practice speed. Listen for words that run together, then try a smoother rhythm.", nil)
        }
        if let ratio = r?.durationRatio, ratio < 0.85 {
            return ("Give the phrase more time", "Your take was about \(Int(((1 - ratio) * 100).rounded()))% shorter than the example at the practice speed. Listen for words the speaker holds longer, then give those words more room.", nil)
        }
        if let v = s.voice, let you = v.you, !you.isEmpty {
            let target = ending(v.src), mine = ending(you)
            if !target.isEmpty, !mine.isEmpty, target != mine {
                let action = target.hasPrefix("goes up") ? "Let your voice rise at the end" : target.hasPrefix("goes down") ? "Let your voice fall at the end" : "Keep the ending level"
                return (action, "The pitch estimate suggests a different ending in your take. Listen to the final words and copy the direction of the voice.", max(0, len - 1.5)...len)
            }
        }
        return ("Focus on the rhythm", "Listen to which words stand out and how the quieter words fit between them. Replay your take, then try copying that pattern.", nil)
    }
}

struct VoiceMapView: View {
    @EnvironmentObject var s: Store
    let phrase: Phrase
    @State private var expanded = false
    var len: Double { max(phrase.end - phrase.start, 0.01) }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            TimelineView(.animation(minimumInterval: 0.05, paused: !(s.recording || s.isPlaying || s.isTakePlaying))) { _ in
                let you = s.live?.track ?? s.voice?.you, head = s.isPlaying ? min(max(0, (s.original?.currentTime ?? phrase.start) - phrase.start), len) : s.position
                VStack(alignment: .leading, spacing: 10) {
                    Canvas { ctx, size in draw(ctx, size, you, head) }.frame(height: 150)
                        .accessibilityLabel("Relative pitch of the example and your take, with quiet gaps")
                        .help("The line rises when the voice goes up and falls when it goes down. Match its shape, not the speaker's natural pitch.")
                    HStack(spacing: 14) {
                        HStack(spacing: 6) { Capsule().fill(Color.pitch).frame(width: 14, height: 3); muted("Example") }
                        if s.recording || you?.isEmpty == false { HStack(spacing: 6) { Capsule().fill(Color.violet).frame(width: 14, height: 3); muted("You") } }
                        muted("Shaded gaps = silence")
                    }
                    muted("Relative pitch. Saved takes are fitted to the example’s length to compare shape; use playback to compare timing.").fixedSize(horizontal: false, vertical: true)
                    if s.voiceFailed { muted("Couldn't load pitch detail. Try switching phrases and returning.") }
                }.padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.subtle)).padding(.top, 8)
            }
        } label: { Text(expanded ? "Pitch detail" : "Show pitch detail").font(.system(size: 12, weight: .medium)) }
    }

    func clock(_ t: Double) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }

    func draw(_ ctx: GraphicsContext, _ size: CGSize, _ you: [Pt]?, _ head: Double) {
        let v = s.voice, src = v?.src ?? [], span = max(len, (you?.last?.x ?? 0) + 0.1)
        let w = size.width, h = size.height, left: CGFloat = 50, right = w - 22, top: CGFloat = 24, bot = h - 28
        let vals = src.compactMap(\.st).sorted()
        var lo = vals.isEmpty ? -3 : vals[Int(Double(vals.count - 1) * 0.03)], hi = vals.isEmpty ? 3 : vals[Int(Double(vals.count - 1) * 0.97)]
        if hi - lo < 6 { let c = (hi + lo) / 2; lo = c - 3; hi = c + 3 }
        let yHi = top + 18, yLo = bot - 18
        func X(_ x: Double) -> CGFloat { left + CGFloat(x / span) * (right - left) }
        func Y(_ st: Double) -> CGFloat { min(bot - 2, max(top + 2, yHi + CGFloat((hi - st) / (hi - lo)) * (yLo - yHi))) }
        func stAt(_ x: Double, _ t: [Pt] = src) -> Double? { t.filter { $0.st != nil && abs($0.x - x) <= 0.15 }.min { abs($0.x - x) < abs($1.x - x) }?.st }
        func line(_ t: [Pt], _ c: Color, _ width: CGFloat) {
            var p = Path(), run: [CGPoint] = [], prev: Double? = nil
            func flush() {
                if run.count > 1 {
                    p.move(to: run[0])
                    for i in 1..<run.count { p.addQuadCurve(to: CGPoint(x: (run[i - 1].x + run[i].x) / 2, y: (run[i - 1].y + run[i].y) / 2), control: run[i - 1]) }
                    p.addLine(to: run[run.count - 1])
                }
                run = []
            }
            for q in t {
                guard let st = q.st else { continue }
                if let pr = prev, q.x - pr >= 0.2 { flush() }
                run.append(CGPoint(x: X(q.x), y: Y(st))); prev = q.x
            }
            flush()
            ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        var placed: [CGRect] = []
        func label(_ s: String, _ at: CGPoint, _ anchor: UnitPoint, _ c: Color, _ size: CGFloat = 10, _ weight: Font.Weight = .regular) {
            let t = ctx.resolve(Text(s).font(.system(size: size, weight: weight)).foregroundColor(c)), m = t.measure(in: CGSize(width: w, height: h))
            let r = CGRect(x: at.x - m.width * anchor.x, y: at.y - m.height * anchor.y, width: m.width, height: m.height)
            guard r.minX >= 0, r.maxX <= w, !placed.contains(where: { $0.insetBy(dx: -4, dy: -2).intersects(r) }) else { return }
            placed.append(r); ctx.draw(t, at: at, anchor: anchor)
        }
        for (y, name) in [(yHi, "Higher"), (yLo, "Lower")] {
            ctx.stroke(Path { $0.move(to: CGPoint(x: left, y: y)); $0.addLine(to: CGPoint(x: right, y: y)) }, with: .color(Color.ink.opacity(0.07)), lineWidth: 1)
            label(name, CGPoint(x: 4, y: y), .leading, .secondary)
        }
        for (a, b) in v?.pauses ?? [] {
            let r = CGRect(x: X(a), y: top, width: X(b) - X(a), height: bot - top)
            ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(Color.warn.opacity(0.09)))
            ctx.stroke(Path(roundedRect: r, cornerRadius: 4), with: .color(Color.warn.opacity(0.65)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            label("\(Int(((b - a) * 100).rounded()) * 10) ms pause", CGPoint(x: r.midX, y: top - 5), .bottom, .secondary, 9.5)
        }
        line(src, Color.ink.opacity(0.07), 9)
        line(src, Color.pitch.opacity(you?.isEmpty == false ? 0.55 : 1), 3.5)
        line(you ?? [], .violet, 2.5)
        let pts = src.filter { $0.st != nil }
        if let first = pts.first, let lastX = pts.last?.x, lastX - first.x > 0.8 {
            let end = ending(src), ex = lastX - 0.3
            if !end.isEmpty, !end.hasPrefix("stays"), let st = stAt(ex) {
                label(end.hasPrefix("goes up") ? "rise ↗" : "fall ↘", CGPoint(x: X(ex), y: max(top + 14, Y(st) - 12)), .bottom, .ink, 10.5, .medium)
            }
            var best: (x: Double, st: Double, d: Double)? = nil
            for q in pts where q.x < lastX - 0.35 {
                let st = q.st!, near = pts.filter { abs($0.x - q.x) <= 0.15 }, before = pts.filter { $0.x >= q.x - 0.7 && $0.x < q.x }
                guard near.allSatisfy({ $0.st! <= st }), let m = before.compactMap(\.st).min(), st - m >= 2.5, st - m > (best?.d ?? 0) else { continue }
                best = (q.x, st, st - m)
            }
            if let b = best { label("rise ↗", CGPoint(x: X(b.x) - 8, y: Y(b.st) - 6), .bottomTrailing, .ink, 10.5, .medium) }
            if let (a, z) = speechSpan(src) {
                let edges = [a] + (v?.pauses ?? []).flatMap { [$0.0, $0.1] } + [z]
                let segs = stride(from: 0, to: edges.count - 1, by: 2).map { (edges[$0], edges[$0 + 1]) }
                if let seg = segs.max(by: { $0.1 - $0.0 < $1.1 - $1.0 }), seg.1 - seg.0 >= 1,
                   (phrase.words ?? []).filter({ ($0.start + $0.end) / 2 - phrase.start >= seg.0 && ($0.start + $0.end) / 2 - phrase.start <= seg.1 }).count >= 3,
                   let peak = pts.filter({ $0.x >= seg.0 && $0.x <= seg.1 }).compactMap(\.st).max() {
                    label("keep connected", CGPoint(x: X((seg.0 + seg.1) / 2), y: max(top + 12, Y(peak) - 10)), .bottom, .secondary, 10)
                }
            }
        }
        let step: Double = len <= 6 ? 1 : len <= 15 ? 2 : 5, tickY = bot + 16
        for t in stride(from: 0, to: len, by: step) where t == 0 || X(len) - X(t) >= 36 { label(clock(t), CGPoint(x: X(t), y: tickY), .center, .secondary, 9.5) }
        label(String(format: "%d:%04.1f", Int(len) / 60, len.truncatingRemainder(dividingBy: 60)), CGPoint(x: X(len), y: tickY), .center, .secondary, 9.5)
        var ph: Double? = nil
        if s.recording, let L = s.live { ph = L.x }
        else if s.isTakePlaying, s.live == nil, let v, v.you != nil, let t = s.takePlayer { ph = t.currentTime * v.scale + v.shift }
        else if s.isPlaying || head > 0 { ph = head }
        if let ph, ph >= 0 {
            ctx.stroke(Path { $0.move(to: CGPoint(x: X(ph), y: top - 2)); $0.addLine(to: CGPoint(x: X(ph), y: bot + 2)) }, with: .color(Color.ink.opacity(0.75)), lineWidth: 1.5)
            if let st = stAt(ph, s.recording ? (you ?? []) : src) { ctx.fill(Path(ellipseIn: CGRect(x: X(ph) - 4, y: Y(st) - 4, width: 8, height: 8)), with: .color(.ink)) }
        }
    }
}

struct Inspector: View {
    @EnvironmentObject var s: Store
    let lesson: Lesson
    var body: some View {
        VStack(spacing: 0) {
            Segmented(options: [(false, "Phrases"), (true, "Feedback")], selection: $s.showFeedback).padding(14)
            Rectangle().fill(Color.line).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView { if s.showFeedback { FeedbackPanel() } else { PhraseList(lesson: lesson) } }
                    .onChange(of: s.index) { i in if !s.showFeedback { withAnimation { proxy.scrollTo(i, anchor: .center) } } }
            }
        }.background(Color.surface.ignoresSafeArea())
    }
}

struct PhraseList: View {
    @EnvironmentObject var s: Store
    let lesson: Lesson
    var body: some View {
        let done = lesson.phrases.filter { $0.practised == true }.count
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(done) of \(lesson.phrases.count) practised").font(.system(size: 12.5, weight: .medium))
                Bar(value: Double(done) / Double(max(1, lesson.phrases.count))).frame(height: 4)
            }.padding(.horizontal, 8).padding(.bottom, 12)
            ForEach(Array(lesson.phrases.enumerated()), id: \.offset) { i, p in
                Button { s.select(i) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text(String(format: "%02d", i + 1)).font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.secondary).padding(.top, 1)
                        Text(p.text).font(.system(size: 12.5)).lineLimit(2).multilineTextAlignment(.leading).foregroundStyle(Color.ink)
                        Spacer(minLength: 4)
                        Image(systemName: p.practised == true ? "checkmark.circle.fill" : "circle").font(.system(size: 12)).foregroundStyle(p.practised == true ? Color.good : Color.secondary.opacity(0.5))
                    }
                }.buttonStyle(RowStyle(active: i == s.index, pad: 8)).disabled(s.locked).id(i)
            }
        }.padding(12)
    }
}

struct TakeHistorySheet: View {
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let takes = s.lesson?.takeHistory ?? []
        let active = Set(s.lesson?.phrases.compactMap(\.revision) ?? [])
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Take history").font(.title2)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if takes.isEmpty {
                Text("No saved takes in this session yet.").foregroundStyle(.secondary)
            } else {
                muted("Practice estimates. Compare takes from the same phrase version and speed.")
                if let error = s.takePlaybackError {
                    Text(error).foregroundStyle(.red)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(takes) { take in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    if let created = take.created {
                                        Text(Date(timeIntervalSince1970: created).formatted(date: .abbreviated, time: .shortened))
                                            .fontWeight(.semibold)
                                    } else {
                                        Text("Date unavailable").fontWeight(.semibold)
                                    }
                                    if take.legacy == true { muted("Legacy take") }
                                    Spacer()
                                    Button(s.playingTakeID == take.id ? "Stop" : "Replay") {
                                        if s.playingTakeID == take.id { s.stopPlayback() }
                                        else { Task { await s.playTake(take) } }
                                    }
                                }
                                if let version = take.phraseRevision {
                                    Text(version.text).fixedSize(horizontal: false, vertical: true)
                                    let label = version.id == s.phrase?.revision ? "Current phrase" :
                                        active.contains(version.id) ? "Another phrase" : "Earlier phrase version"
                                    muted("\(label) · \(fmt(version.start)) – \(fmt(version.end))")
                                }
                                muted(take.playbackSpeed.map { "\(speedLabel($0)) speed" } ?? "Speed unavailable")
                                muted("Word accuracy \(take.accuracy)% · Pace & rhythm \(take.rhythm)% · Intonation \(take.intonation.map { "\($0)%" } ?? "N/A")")
                                if !take.tips.isEmpty {
                                    DisclosureGroup("Feedback") {
                                        ForEach(take.tips, id: \.self) { tip in
                                            Text(tip).fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                Divider()
                            }
                        }
                    }
                }.frame(height: 380)
            }
        }.padding(24).frame(width: 530)
    }
}

struct FeedbackPanel: View {
    @EnvironmentObject var s: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let r = s.phrase?.latest {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest take").font(.system(size: 15, weight: .semibold))
                    muted("Practice estimates at \(speedLabel(r.playbackSpeed ?? 1)) speed, not pronunciation grades. Listen back to judge the details.").fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 16) {
                    score("Word accuracy", "Did the words come through?", r.accuracy)
                    score("Pace & rhythm", "Timing, pauses and energy", r.rhythm)
                    score("Intonation", "The rise and fall of your voice", r.intonation)
                }
                if !r.tips.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Try next").font(.system(size: 13, weight: .semibold))
                        ForEach(r.tips, id: \.self) { t in HStack(alignment: .top, spacing: 8) { Image(systemName: "sparkle").font(.system(size: 10)).foregroundStyle(Color.violet).padding(.top, 3); Text(t).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true) } }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(Color.violet.opacity(0.08)))
                }
            } else {
                VStack(spacing: 10) {
                    Orb(seed: "feedback", size: 52)
                    Text("No feedback yet").font(.system(size: 15, weight: .semibold))
                    Text("Record a take of this phrase to see how your words, rhythm and pitch follow the speaker.").font(.system(size: 12.5)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    muted("Use headphones for a cleaner comparison.")
                }.frame(maxWidth: .infinity).padding(.vertical, 28)
            }
            DisclosureGroup {
                Text("These are practice estimates, not validated pronunciation grades. Word accuracy compares speech recognition with the phrase text; it does not assess individual speech sounds. Rhythm uses duration and loudness patterns. Intonation compares relative pitch contours; music and noisy recordings can affect it. Audio extraction keeps background sounds—it does not isolate the speaker. Bold words are louder in the example, which does not always mean stressed. Pause markers indicate estimated quiet gaps of 0.15 seconds or more between words. The ending arrow estimates the final pitch direction. Show pitch detail opens the relative pitch curves. A saved take is stretched to the speaker's length in that chart; pace suggestions use the original duration comparison instead.").font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            } label: { Text("How feedback works").font(.system(size: 12, weight: .medium)) }
        }.padding(20)
    }
    func score(_ title: String, _ sub: String, _ v: Int?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) { Text(title).font(.system(size: 13, weight: .medium)); muted(sub) }
                Spacer()
                Text(v.map { "\($0)%" } ?? "N/A").font(.system(size: 20, weight: .semibold)).monospacedDigit()
            }
            Bar(value: Double(v ?? 0) / 100).frame(height: 4)
        }
    }
}

// MARK: Sheets

struct ImportSheet: View {
    @EnvironmentObject var s: Store
    @State var picking = false
    @State var dropping = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New practice session").font(.system(size: 20, weight: .semibold)).tracking(-0.3)
                    muted("Choose clear speech from one speaker. Short clips with little background music work best.").fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { s.showImport = false } label: { Image(systemName: "xmark") }.buttonStyle(RoundStyle(size: 26)).keyboardShortcut(.cancelAction)
            }
            Segmented(options: [(false, "YouTube link"), (true, "Upload a file")], selection: $s.importUpload)
            if s.importUpload {
                Button { picking = true } label: {
                    VStack(spacing: 8) {
                        Image(systemName: s.importFile == nil ? "arrow.up.circle" : "doc.fill").font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
                        Text(s.importFile?.lastPathComponent ?? "Click to choose, or drop a file here").font(.system(size: 13, weight: .medium)).lineLimit(1)
                        muted("MP3, WAV, M4A, MP4, WebM · up to 150 MB · up to 30 minutes")
                        muted("Or a PDF with selectable English or French text, read aloud by an ElevenLabs voice you choose")
                    }.frame(maxWidth: .infinity).padding(.vertical, 26)
                        .background(RoundedRectangle(cornerRadius: 12).fill(dropping ? Color.selected : Color.subtle))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5])).foregroundStyle(Color.line))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                .onDrop(of: [UTType.fileURL], isTargeted: $dropping) { providers in
                    guard let p = providers.first else { return false }
                    _ = p.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in s.importFile = url; s.importURL = ""; s.importError = "" } } }
                    return true
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Video link").font(.system(size: 12, weight: .medium))
                    TextField("https://www.youtube.com/watch?v=…", text: Binding(get: { s.importURL }, set: { s.importURL = $0; if !$0.isEmpty { s.importFile = nil } }))
                        .textFieldStyle(.plain).padding(.horizontal, 12).padding(.vertical, 9).panel(10)
                    muted("Up to 30 minutes. Import content you have permission to use.")
                }
            }
            Picker("Lesson language", selection: $s.importLanguage) {
                Text("English").tag("en")
                Text("French").tag("fr")
            }.pickerStyle(.segmented)
            if s.importUpload && s.importFile?.pathExtension.lowercased() == "pdf" { PDFVoicePicker() }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 2)
                muted(s.importUpload && s.importFile?.pathExtension.lowercased() == "pdf" ? "The text of this PDF (the first 20,000 characters) is sent to ElevenLabs to create the voice, using your ElevenLabs account and credits. Your recordings stay on your Mac." : "Processing and recordings stay on your Mac. Importing a link connects to YouTube; the first transcription downloads a speech model.").fixedSize(horizontal: false, vertical: true)
            }
            if !s.importError.isEmpty { Text(s.importError).foregroundStyle(Color.rec).font(.system(size: 12.5)) }
            HStack { Spacer(); Button("Cancel") { s.showImport = false }.buttonStyle(PillStyle()); Button("Create session") { create() }.buttonStyle(PillStyle(primary: true)).keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 520).background(Color.surface)
        .onDisappear { s.stopSample() }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio, .movie, .audiovisualContent, .pdf] + ["webm", "mkv", "m4a"].compactMap { UTType(filenameExtension: $0) }) { result in
            if case .success(let url) = result { s.importFile = url; s.importURL = ""; s.importError = "" }
        }
    }
    func create() {
        if s.importUpload {
            if s.importFile == nil { s.importError = "Choose an audio, video or PDF file."; return }
            s.importURL = ""
        } else { s.importFile = nil }
        Task { await s.submitImport() }
    }
}

struct PDFVoicePicker: View {
    @EnvironmentObject var s: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reading voice").font(.system(size: 12, weight: .medium))
            if s.pdfVoices.isEmpty {
                if s.pdfVoiceError.isEmpty { HStack(spacing: 8) { ProgressView().controlSize(.small); muted("Loading your ElevenLabs voices…") } }
                else { Text(s.pdfVoiceError).foregroundStyle(Color.rec).font(.system(size: 12.5)); Button("Try again") { Task { await s.loadPDFVoices() } }.buttonStyle(PillStyle(compact: true)) }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(s.pdfVoices) { v in
                        HStack(spacing: 8) {
                            Button { s.toggleSample(v) } label: { Image(systemName: s.sampleVoice == v.id ? "stop.fill" : "play.fill").font(.system(size: 10)) }.buttonStyle(RoundStyle(size: 24)).help("Hear a short sample of \(v.name)")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(v.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                Text([v.gender, v.accent].filter { !$0.isEmpty }.joined(separator: " · ").capitalized).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if s.pdfVoice == v.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary) }
                        }
                        .padding(8).background(RoundedRectangle(cornerRadius: 10).fill(s.pdfVoice == v.id ? Color.selected : Color.subtle))
                        .contentShape(Rectangle()).onTapGesture { s.selectPDFVoice(v.id) }
                        .accessibilityElement(children: .contain)
                    }
                }
                muted("Samples are free to play. Only the final reading uses your ElevenLabs credits.")
            }
        }
        .task(id: s.importLanguage) { await s.loadPDFVoices() }
        .onDisappear { s.stopSample() }
    }
}

struct EditSheet: View {
    @EnvironmentObject var s: Store
    @State var text = ""
    @State var start = 0.0
    @State var end = 0.0
    @State var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit phrase").font(.system(size: 20, weight: .semibold)).tracking(-0.3)
                muted("Changing the text or timing starts a new phrase version. Earlier recordings and feedback stay in Take history.")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Text").font(.system(size: 12, weight: .medium))
                TextEditor(text: $text).font(.system(size: 13)).scrollContentBackground(.hidden).padding(8).frame(height: 96).panel(10)
            }
            HStack(spacing: 12) { field("Start (seconds)", $start); field("End (seconds)", $end) }
            muted("Keep phrases under 30 seconds. Correct the text before comparing takes.")
            if !error.isEmpty { Text(error).foregroundStyle(Color.rec).font(.system(size: 12.5)) }
            HStack { Spacer(); Button("Cancel") { s.showEdit = false }.buttonStyle(PillStyle()).keyboardShortcut(.cancelAction); Button("Save phrase") { Task { if let e = await s.savePhrase(text: text, start: start, end: end) { error = e } else { s.showEdit = false } } }.buttonStyle(PillStyle(primary: true)).keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 480).background(Color.surface)
        .onAppear { if let p = s.phrase { text = p.text; start = p.start; end = p.end } }
    }
    func field(_ label: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(label).font(.system(size: 12, weight: .medium)); TextField("", value: value, format: .number.precision(.fractionLength(0...2))).textFieldStyle(.plain).padding(.horizontal, 10).padding(.vertical, 8).panel(10) }
    }
}
