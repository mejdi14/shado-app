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
}

extension View {
    func panel(_ r: CGFloat = 14) -> some View { background(RoundedRectangle(cornerRadius: r).fill(Color.surface)).overlay(RoundedRectangle(cornerRadius: r).stroke(Color.line)) }
}

func muted(_ s: String) -> some View { Text(s).font(.system(size: 12)).foregroundStyle(.secondary) }
func legendDot(_ c: Color, _ t: String) -> some View { HStack(spacing: 6) { Circle().fill(c).frame(width: 7, height: 7); muted(t) } }
func sourceLabel(_ source: String, _ sample: Bool) -> String { sample ? "Guided sample · built-in Mac voice" : source.hasPrefix("http") ? "YouTube" : "Your file" }
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
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) { Orb(seed: "shadow studio", size: 22); Text("Shadow Studio").font(.system(size: 15, weight: .semibold)).tracking(-0.2) }.padding(.horizontal, 8).padding(.bottom, 18)
            Button { s.stopPlayback(); s.showImport = true } label: { Label("New session", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(PillStyle(primary: true)).disabled(s.locked).padding(.bottom, 16)
            nav("Home", "square.grid.2x2", active: s.showLibrary) { Task { await s.openLibrary() } }
            nav("Practice", "waveform", active: !s.showLibrary) { s.showLibrary = false }
            if !s.library.isEmpty {
                Text("Sessions").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.top, 20).padding(.bottom, 4)
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(s.library) { l in
                            Button { Task { await s.openLesson(l.id) } } label: { HStack(spacing: 9) { Orb(seed: l.id, size: 16); Text(l.title).lineLimit(1); Spacer(minLength: 0) } }
                                .buttonStyle(RowStyle(active: !s.showLibrary && s.lesson?.id == l.id)).disabled(s.locked)
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
    func nav(_ title: String, _ icon: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack(spacing: 9) { Image(systemName: icon).frame(width: 16); Text(title).fontWeight(active ? .medium : .regular); Spacer(minLength: 0) } }
            .buttonStyle(RowStyle(active: active, pad: 7)).disabled(s.locked)
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

// MARK: Home

struct LibraryView: View {
    @EnvironmentObject var s: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Home").font(.system(size: 28, weight: .semibold)).tracking(-0.6)
                Text("Pick up a session, or bring in a new voice to practise with.").foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                tile("Import from YouTube", "Paste a link to an English video", "play.fill", "youtube") { s.importUpload = false; s.showImport = true }
                tile("Upload a file", "Audio or video from your Mac", "arrow.up", "upload") { s.importUpload = true; s.showImport = true }
                tile("Try the sample", "A short guided example", "sparkles", "sample") { if let id = s.sampleId { Task { await s.openLesson(id) } } }.disabled(s.sampleId == nil)
            }
            VStack(spacing: 0) {
                HStack { Text("Sessions").font(.system(size: 15, weight: .semibold)); Spacer(); muted("\(s.library.count)") }.padding(.horizontal, 18).padding(.vertical, 14)
                Rectangle().fill(Color.line).frame(height: 1)
                if s.library.isEmpty { muted("No sessions yet. Import a clip to create your first one.").frame(maxWidth: .infinity).padding(32) }
                VStack(spacing: 2) {
                    ForEach(s.library) { l in
                        Button { Task { await s.openLesson(l.id) } } label: {
                            HStack(spacing: 14) {
                                Orb(seed: l.id, size: 32)
                                VStack(alignment: .leading, spacing: 2) { Text(l.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1).foregroundStyle(Color.ink); muted(sourceLabel(l.source, l.sample)) }
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
    var body: some View {
        if let l = s.lesson, let p = s.phrase {
            HStack(spacing: 0) {
                ScrollView { PracticePanel(lesson: l, phrase: p).padding(32).frame(maxWidth: 880).frame(maxWidth: .infinity) }
                Rectangle().fill(Color.line).frame(width: 1).ignoresSafeArea()
                Inspector(lesson: l).frame(width: 330)
            }
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
                Text("Practise speaking English,\none phrase at a time.").font(.system(size: 28, weight: .semibold)).tracking(-0.6).multilineTextAlignment(.center)
                Text("Bring in a clip of a speaker you like. Shadow Studio splits it into short phrases you can listen to, repeat and compare.").foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 470)
            }
            HStack(spacing: 10) {
                Button { s.showImport = true } label: { Label("New session", systemImage: "plus") }.buttonStyle(PillStyle(primary: true))
                Button("Try the sample") { if let id = s.sampleId { Task { await s.openLesson(id) } } }.buttonStyle(PillStyle()).disabled(s.sampleId == nil)
            }
            HStack(alignment: .top, spacing: 12) {
                how(1, "Import", "A YouTube link or an audio or video file.")
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
    @EnvironmentObject var s: Store
    let lesson: Lesson
    let phrase: Phrase
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
                Menu {
                    Button("Edit this phrase…") { s.stopPlayback(); s.showEdit = true }
                    Divider()
                    Button("Delete session…", role: .destructive) { s.stopPlayback(); s.showDelete = true }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(s.locked).help("More")
            }
            VStack(alignment: .leading, spacing: 8) {
                Segmented(options: Mode.allCases.map { ($0, $0.title) }, selection: Binding(get: { s.mode }, set: { s.setMode($0) })).frame(maxWidth: 340).disabled(s.locked)
                muted(s.mode.hint)
            }
            phraseCard
            HStack(alignment: .top, spacing: 12) { listen; record; compare }.fixedSize(horizontal: false, vertical: true)
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
                Text(phraseText(phrase)).font(.system(size: 26)).tracking(-0.3).lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                if phrase.latest != nil { HStack(spacing: 14) { legendDot(.good, "Heard clearly"); legendDot(.warn, "Not recognised"); Spacer() } }
            }
            VoiceMapView(phrase: phrase)
        }.padding(24).panel(16)
    }

    var listen: some View {
        StepCard(n: 1, title: "Listen", detail: "Play the original. Repeat it as often as you like.", active: phrase.latest == nil && !s.recording) {
            HStack(spacing: 8) {
                Button { s.togglePlay() } label: { Image(systemName: s.isPlaying ? "pause.fill" : "play.fill") }
                    .buttonStyle(RoundStyle(size: 44, fill: .ink, fg: .inkInverse, border: false)).keyboardShortcut(.space, modifiers: []).help("Play the original phrase (Space)")
                Spacer(minLength: 0)
                Menu { ForEach([0.65, 0.8, 1.0, 1.15], id: \.self) { v in Button(speedLabel(v)) { s.speed = v } } } label: { Text(speedLabel(s.speed)) }
                    .menuStyle(.borderlessButton).fixedSize().disabled(s.locked).help("Playback speed")
                Button { s.looping.toggle() } label: { Image(systemName: "repeat") }.buttonStyle(RoundStyle(size: 30, fill: s.looping ? .selected : .surface)).help(s.looping ? "Loop is on" : "Loop this phrase")
            }
        }
    }

    var record: some View {
        StepCard(n: 2, title: "Record", detail: recordDetail, active: s.recording) {
            HStack(spacing: 10) {
                Button { Task { await s.toggleRecording() } } label: { Image(systemName: s.recording ? "stop.fill" : "mic.fill") }
                    .buttonStyle(RoundStyle(size: 44, fill: .rec, fg: .white, border: false))
                    .background { if s.recording { Pulse() } }
                    .keyboardShortcut("r", modifiers: []).disabled(s.starting || s.stopping || s.busy != nil).help(s.recording ? "Stop recording (R)" : "Record a take (R)")
                if s.recording { VStack(alignment: .leading, spacing: 1) { Text(fmt(s.recordSeconds)).font(.system(size: 15, weight: .semibold)).monospacedDigit(); muted("Recording…") } }
                else if s.starting || s.stopping { ProgressView().controlSize(.small) }
            }
        }
    }

    var recordDetail: String {
        switch s.mode {
        case .listen: return "Say the phrase the way you heard it."
        case .recall: return "Say it from memory. The text stays hidden."
        case .shadow: return "The original plays as you record. Speak along, with headphones."
        }
    }

    var compare: some View {
        let takes = phrase.takes ?? 1
        let buttons = Group {
            Button { Task { await s.toggleTake() } } label: { Label(s.isTakePlaying ? "Stop" : "Your take", systemImage: s.isTakePlaying ? "stop.fill" : "play.fill") }.buttonStyle(PillStyle(compact: true))
            Button { s.compareAB() } label: { Label("Original → you", systemImage: "arrow.left.arrow.right") }.buttonStyle(PillStyle(compact: true)).help("Play the original, then your take")
        }
        return StepCard(n: 3, title: "Compare", detail: phrase.latest == nil ? "Record a take first, then listen back." : "\(takes) take\(takes > 1 ? "s" : "") so far. Hear yours, or the original then you.", active: phrase.latest != nil && !s.recording) {
            ViewThatFits(in: .horizontal) { HStack(spacing: 8) { buttons }; VStack(alignment: .leading, spacing: 6) { buttons } }
                .disabled(phrase.latest == nil || s.locked)
        }
    }

    func phraseText(_ p: Phrase) -> AttributedString {
        guard let marks = p.latest?.words else { return AttributedString(p.text) }
        let re = try! NSRegularExpression(pattern: "[a-z]+(?:['’][a-z]+)?", options: .caseInsensitive)
        let ns = p.text as NSString
        var out = AttributedString(), last = 0, i = 0
        for m in re.matches(in: p.text, range: NSRange(location: 0, length: ns.length)) {
            out += AttributedString(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            var w = AttributedString(ns.substring(with: m.range))
            if i < marks.count && marks[i].match { w.foregroundColor = .good } else { w.foregroundColor = .warn; w.underlineStyle = .single }
            out += w; last = m.range.location + m.range.length; i += 1
        }
        out += AttributedString(ns.substring(from: last))
        return out
    }
}

struct VoiceMapView: View {
    @EnvironmentObject var s: Store
    let phrase: Phrase
    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !(s.recording || s.isPlaying || s.isTakePlaying))) { _ in
            let you = s.live?.track ?? s.voice?.you
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Text("How it sounds").font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    legendDot(Color.ink.opacity(0.4), "Speaker")
                    if s.recording || you?.isEmpty == false { legendDot(.violet, "You") }
                }
                Canvas { ctx, size in draw(ctx, size, you) }.frame(height: 116)
                    .accessibilityLabel("The speaker's voice going up and down, with the words underneath")
                if let v = s.voice {
                    muted("The line rises when the voice goes up and falls when it goes down. Match its shape, not the speaker's natural pitch.").fixedSize(horizontal: false, vertical: true)
                    guide(v, s.recording ? nil : you)
                } else if s.voiceFailed { muted("Couldn't load the speaker's voice. Quit Shadow Studio and any Terminal window running it, then open it again.") }
            }
        }
    }

    func clean(_ w: String) -> String { w.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) }

    func guide(_ v: VoiceMap, _ you: [Pt]?) -> some View {
        let words = phrase.words ?? []
        let strong = v.stress.sorted().filter { $0 < words.count }.prefix(4).map { clean(words[$0].word) }
        let after = v.pauses.compactMap { p in words.last { $0.start - phrase.start < p.0 }.map { "“\(clean($0.word))”" } }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let end = ending(v.src), mine = you?.isEmpty == false ? you : nil
        let n = pauses(mine ?? []).count, yEnd = ending(mine ?? [])
        return HStack(alignment: .top, spacing: 10) {
            tip("Say these stronger", strong.isEmpty ? "No word stands out" : strong.joined(separator: ", "), nil, false)
            tip("Pause", after.isEmpty ? "None. Say it in one go." : "After " + after.joined(separator: ", "), mine.map { _ in n == 0 ? "no pauses" : "\(n) pause\(n > 1 ? "s" : "")" }, n == v.pauses.count)
            tip("At the end, the voice", end.isEmpty ? "Hard to tell" : end, mine.map { _ in yEnd.isEmpty ? "hard to tell" : yEnd }, !end.isEmpty && yEnd == end)
        }
    }

    func tip(_ title: String, _ value: String, _ yours: String?, _ ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            if let yours {
                HStack(spacing: 4) { Text("You: " + yours); if ok { Image(systemName: "checkmark") } }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(ok ? Color.good : Color.violet).padding(.top, 2)
            }
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(RoundedRectangle(cornerRadius: 10).fill(Color.subtle))
    }

    func draw(_ ctx: GraphicsContext, _ size: CGSize, _ you: [Pt]?) {
        let v = s.voice, src = v?.src ?? [], span = max(phrase.end - phrase.start, (you?.last?.x ?? 0) + 0.1)
        let w = size.width, h = size.height, top: CGFloat = 16, bot = h - 30, mid = (top + bot) / 2
        func X(_ x: Double) -> CGFloat { CGFloat(x / span) * w }
        func Y(_ st: Double) -> CGFloat { mid - CGFloat(max(-9, min(9, st))) * (bot - top) / 20 }
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
        for (a, b) in v?.pauses ?? [] {
            ctx.fill(Path(roundedRect: CGRect(x: X(a), y: top - 6, width: X(b) - X(a), height: bot - top + 12), cornerRadius: 4), with: .color(Color.rose.opacity(0.08)))
            if X(b) - X(a) >= 26 { ctx.draw(Text("pause").font(.system(size: 9, weight: .medium)).foregroundColor(.rose), at: CGPoint(x: X((a + b) / 2), y: top - 3), anchor: .top) }
        }
        line(src, Color.ink.opacity(you?.isEmpty == false ? 0.3 : 0.45), 3.5)
        line(you ?? [], .violet, 2.5)
        var ph: Double? = nil
        if s.recording, let L = s.live { ph = L.x }
        else if s.isPlaying, let p = s.original { ph = p.currentTime - phrase.start }
        else if s.isTakePlaying, s.live == nil, let v, v.you != nil, let t = s.takePlayer { ph = t.currentTime * v.scale + v.shift }
        var last: CGFloat = -1
        for (i, wd) in (phrase.words ?? []).enumerated() {
            let a = wd.start - phrase.start, b = wd.end - phrase.start, c = X((a + b) / 2), em = v?.stress.contains(i) ?? false, now = ph.map { $0 >= a && $0 < b } ?? false
            let txt = ctx.resolve(Text(wd.word.trimmingCharacters(in: .whitespaces)).font(.system(size: em ? 13 : 12, weight: em ? .bold : .regular)).foregroundColor(em || now ? .ink : .secondary))
            let sz = txt.measure(in: size)
            guard c - sz.width / 2 > last + 4 else { continue }
            if now { ctx.fill(Path(roundedRect: CGRect(x: c - sz.width / 2 - 5, y: h - sz.height - 5, width: sz.width + 10, height: sz.height + 4), cornerRadius: 6), with: .color(Color.violet.opacity(0.14))) }
            ctx.draw(txt, at: CGPoint(x: c, y: h - 3), anchor: .bottom); last = c + sz.width / 2
        }
        if let ph, ph >= 0 { ctx.stroke(Path { $0.move(to: CGPoint(x: X(ph), y: top - 6)); $0.addLine(to: CGPoint(x: X(ph), y: bot + 4)) }, with: .color(Color.ink.opacity(0.35)), lineWidth: 1) }
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
                Text("These are practice estimates, not validated pronunciation grades. Word accuracy compares speech recognition with the phrase text; it does not assess individual speech sounds. Rhythm uses duration and loudness patterns. Intonation compares relative pitch contours; music and noisy recordings can affect it. Audio extraction keeps background sounds—it does not isolate the speaker. The line under the phrase follows the voice going up and down, relative to each speaker's own pitch. Pauses are quiet gaps of 0.2 seconds or more. Bold words are simply the loudest ones, which are often but not always the stressed words. A saved take is stretched to the speaker's length so the lines line up.").font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
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
                    muted("Choose clear English speech from one speaker. Short clips with little background music work best.").fixedSize(horizontal: false, vertical: true)
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
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 2)
                muted("Processing and recordings stay on your Mac. Importing a link connects to YouTube; the first transcription downloads a speech model.").fixedSize(horizontal: false, vertical: true)
            }
            if !s.importError.isEmpty { Text(s.importError).foregroundStyle(Color.rec).font(.system(size: 12.5)) }
            HStack { Spacer(); Button("Cancel") { s.showImport = false }.buttonStyle(PillStyle()); Button("Create session") { create() }.buttonStyle(PillStyle(primary: true)).keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 520).background(Color.surface)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio, .movie, .audiovisualContent] + ["webm", "mkv", "m4a"].compactMap { UTType(filenameExtension: $0) }) { result in
            if case .success(let url) = result { s.importFile = url; s.importURL = ""; s.importError = "" }
        }
    }
    func create() {
        if s.importUpload {
            if s.importFile == nil { s.importError = "Choose an audio or video file."; return }
            s.importURL = ""
        } else { s.importFile = nil }
        Task { await s.submitImport() }
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
                muted("Fix the text or trim the timing. Saving clears this phrase's old feedback.")
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
