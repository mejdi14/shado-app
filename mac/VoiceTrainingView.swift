import SwiftUI

struct VoiceTrainingView: View {
    @EnvironmentObject var t: VoiceTrainingStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 24)
            tabs
            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    levels.frame(width: 188)
                    VStack(alignment: .leading, spacing: 20) {
                        explanation
                        practice
                        Text("Practice estimates, not pronunciation grades. Your natural voice is the starting point.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(32)
            }
        }
        .foregroundStyle(Color.ink)
        .task { await t.loadProgress() }
        .onDisappear { t.leave() }
    }

    var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("VOICE TRAINING").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(Color.violet)
                Text("Find your voice.").font(.system(size: 30, weight: .semibold)).tracking(-1)
                Text("One skill at a time. A little practice before you shadow.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Label("Start simple. Repeat often.", systemImage: "sparkle")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.violet)
                .padding(.horizontal, 13).padding(.vertical, 9).background(Capsule().fill(Color.violet.opacity(0.08)))
        }
    }

    var tabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 6) {
                    ForEach(VoiceTechnique.allCases) { technique in
                        let selected = t.technique == technique
                        Button {
                            t.select(technique)
                            withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(technique.id, anchor: .center) }
                        } label: {
                            VStack(spacing: 10) {
                                HStack(spacing: 7) {
                                    Image(systemName: technique.icon).font(.system(size: 12))
                                    Text(technique.title).font(.system(size: 12, weight: selected ? .semibold : .medium))
                                    Text("\(t.count(technique))/\(technique.exercises.count)").font(.system(size: 10)).monospacedDigit().opacity(0.65)
                                }
                                .foregroundStyle(selected ? Color.violet : Color.secondary)
                                .padding(.horizontal, 10)
                                Capsule().fill(selected ? Color.violet : Color.clear).frame(height: 2)
                            }.padding(.top, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(t.locked || t.saving).id(technique.id)
                        .accessibilityLabel("\(technique.title), \(t.count(technique)) of \(technique.exercises.count) exercises practised\(selected ? ", selected" : "")")
                    }
                }.padding(.horizontal, 24)
            }.overlay(alignment: .bottom) { Rectangle().fill(Color.line).frame(height: 1) }
        }
    }

    var levels: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Your \(t.technique.title.lowercased()) practice").font(.system(size: 12, weight: .semibold))
                    if t.loadingProgress { ProgressView().controlSize(.mini) }
                }
                Bar(value: Double(t.count(t.technique)) / Double(t.technique.exercises.count)).frame(height: 4)
                Text("\(t.count(t.technique)) / \(t.technique.exercises.count) exercises practised").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.bottom, 4)
            VStack(spacing: 4) {
                ForEach(t.technique.exercises.indices, id: \.self) { i in
                    let ex = t.technique.exercises[i], active = t.level == i
                    Button { t.select(t.technique, level: i) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            ZStack {
                                Circle().fill(active ? Color.violet.opacity(0.13) : Color.subtle)
                                if t.isCompleted(ex) { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.good) }
                                else { Text("\(i + 1)").font(.system(size: 10, weight: .medium)).foregroundStyle(active ? Color.violet : Color.secondary) }
                            }.frame(width: 23, height: 23)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Level \(i + 1)").font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(ex.title).font(.system(size: 12, weight: active ? .semibold : .regular)).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }.padding(.vertical, 5)
                    }.buttonStyle(RowStyle(active: active, pad: 5)).disabled(t.locked || t.saving)
                    .accessibilityLabel("Level \(i + 1), \(ex.title)\(t.isCompleted(ex) ? ", practised" : "")\(active ? ", selected" : "")")
                }
            }
            Divider().padding(.vertical, 4)
            Label {
                Text(t.technique.bridge).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            } icon: { Image(systemName: "arrow.turn.down.right").font(.system(size: 11)) }
            .foregroundStyle(.secondary)
            if t.technique == .connected {
                Text("A next step for confident beginners. Explore whenever you feel ready.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let error = t.progressError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).font(.system(size: 11)).foregroundStyle(Color.warn)
                    Button("Retry progress sync") { Task { await t.loadProgress() } }.buttonStyle(PillStyle(compact: true)).disabled(t.loadingProgress)
                }
            }
        }
    }

    var explanation: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: t.technique.icon).foregroundStyle(Color.violet)
                Text("What is \(t.technique.title.lowercased())?").font(.system(size: 15, weight: .semibold))
            }
            Text(t.technique.explanation).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }

    var practice: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LEVEL \(t.level + 1) · \(t.technique.title.uppercased())").font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(Color.violet)
                    Text(t.exercise.title).font(.system(size: 20, weight: .semibold)).tracking(-0.4)
                }
                Spacer()
                if t.isCompleted(t.exercise) { Label("Practised", systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Color.good) }
            }.padding(22)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                sectionLabel("01", "Hear it", t.exercise.isTone ? "Listen as often as you like." : "First play uses ElevenLabs credits; saved examples replay offline.")
                HStack(spacing: 9) {
                    Button { Task { await t.playExample() } } label: {
                        Label(t.rendering ? "Preparing…" : t.playing ? "Stop example" : "Hear target", systemImage: t.playing || t.rendering ? "stop.fill" : "play.fill")
                    }.buttonStyle(PillStyle(primary: true)).disabled(t.locked)
                    if t.exercise.contrast != nil {
                        Button(t.exercise.contrastLabel) { Task { await t.playExample(contrast: true) } }
                            .buttonStyle(PillStyle()).disabled(t.locked || t.rendering || t.playing)
                    }
                }
                Text(t.exercise.isTone ? "Synthesized tone guide · imitate the movement with your voice" : "ElevenLabs · Bella · American English · saved after first generation")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(22)
            Divider().padding(.horizontal, 22)
            VStack(alignment: .leading, spacing: 15) {
                sectionLabel("02", "See it", visualCaption)
                TrainingVisualization().environmentObject(t)
            }.padding(22)
            Divider().padding(.horizontal, 22)
            VStack(alignment: .leading, spacing: 16) {
                sectionLabel("03", "Try it", "Your turn. Keep it relaxed.")
                Text(t.exercise.instruction).font(.system(size: 13)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button { Task { await t.toggleRecording() } } label: {
                        Label(t.starting ? "Opening microphone…" : t.recording ? "Stop recording" : "Record your voice", systemImage: t.recording ? "stop.fill" : "mic.fill")
                    }.buttonStyle(PillStyle(primary: true)).disabled(t.starting || t.rendering || t.saving || (t.technique == .pace && !t.heardExample))
                    if t.recording {
                        HStack(spacing: 7) { Circle().fill(Color.rec).frame(width: 7, height: 7); Text(String(format: "%.1fs / %.0fs", t.seconds, t.limit)).monospacedDigit() }
                            .font(.system(size: 11)).foregroundStyle(.secondary).accessibilityLabel("Recording, \(Int(t.seconds)) seconds")
                    } else if t.takeURL != nil {
                        Button { t.playTake() } label: { Label(t.playingTake ? "Stop take" : "Hear your take", systemImage: t.playingTake ? "stop.fill" : "play.fill") }
                            .buttonStyle(PillStyle()).disabled(t.rendering)
                    }
                }
                if !t.recording {
                    Text("Microphone starts only when you record. Takes are temporary and stay on this Mac.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if let error = t.error { Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(Color.warn).fixedSize(horizontal: false, vertical: true) }
                if let feedback = t.feedback { feedbackView(feedback) }
            }.padding(22)
        }.panel(18)
    }

    var visualCaption: String {
        switch t.technique {
        case .pitch, .intonation: return "Follow the shape, in your own pitch range."
        case .stress: return "Make the highlighted part stand out."
        case .rhythm: return "Strong beats, light syllables in between."
        case .pace: return "Follow the timeline at a steady pace."
        case .pauses: return "Keep each group together. Pause at the dividers."
        case .energy: return "Stronger and softer, within a comfortable volume."
        case .articulation: return "Slow, clear mouth movements."
        case .connected: return "Listen slowly → hear it naturally → try it."
        }
    }

    func sectionLabel(_ number: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 8) {
            Text(number).font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.violet)
                .frame(width: 24, height: 24).background(Circle().fill(Color.violet.opacity(0.08)))
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 4)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }

    func feedbackView(_ feedback: TrainingFeedback) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: feedback.good ? "checkmark.circle.fill" : "ear.badge.waveform").foregroundStyle(feedback.good ? Color.good : Color.violet)
                VStack(alignment: .leading, spacing: 5) {
                    Text(feedback.title).font(.system(size: 14, weight: .semibold))
                    Text(feedback.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 9) {
                Button { t.resetTake(); Task { await t.toggleRecording() } } label: { Label("Try Again", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(PillStyle(primary: !feedback.good)).disabled(t.locked || t.saving)
                if t.technique.selfReview && feedback.usable && !t.savedThisTake {
                    Button(t.heardTake ? "Sounds clear · mark practised" : "Replay your take to review") { Task { await t.markPracticed() } }.buttonStyle(PillStyle()).disabled(!t.heardTake || t.saving || t.playing || t.playingTake || t.rendering)
                } else if feedback.good && !t.savedThisTake && !t.saving {
                    Button("Save practice") { Task { await t.markPracticed() } }.buttonStyle(PillStyle())
                }
                if t.saving { ProgressView().controlSize(.small) }
                if t.savedThisTake {
                    if t.level + 1 < t.technique.exercises.count {
                        Button { t.select(t.technique, level: t.level + 1) } label: { Label("Next level", systemImage: "arrow.right") }.buttonStyle(PillStyle())
                    } else { Text("You can revisit any level.").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            }
        }.padding(16).background(RoundedRectangle(cornerRadius: 12).fill(feedback.good ? Color.good.opacity(0.06) : Color.violet.opacity(0.045)))
        .accessibilityElement(children: .contain)
    }
}

struct TrainingVisualization: View {
    @EnvironmentObject var t: VoiceTrainingStore
    var ex: VoiceExercise { t.exercise }
    var skill: VoiceTechnique { t.technique }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if skill == .stress || skill == .rhythm { syllables }
            else if skill == .pauses { phraseGroups }
            else {
                Text(ex.prompt).font(.system(size: skill == .articulation ? 26 : 23, weight: .medium)).tracking(-0.3)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8).multilineTextAlignment(.center)
            }
            if skill == .pace { paceTimeline }
            else { contour.frame(height: skill.usesPitch ? 150 : 105) }
            HStack(spacing: 16) {
                if !skill.selfReview { legendDot(.violet, skill == .stress || skill == .rhythm ? "Target energy" : "Target") }
                legendDot(.pitch, t.recording ? "Your voice · live" : "Your voice")
                Spacer()
                if skill == .energy { Text("softer ↑ stronger").font(.system(size: 10)).foregroundStyle(.secondary) }
                else if skill.usesPitch { Text(ex.pattern.cue).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            if skill.selfReview {
                Text("The trace shows sound activity. Use playback to judge clarity and connections; no phoneme analysis is used.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else if skill == .stress || skill == .rhythm {
                Text("Energy groups are approximate. Listen back to check the syllables and words.").font(.system(size: 10)).foregroundStyle(.secondary)
            } else if skill.usesPitch && !t.frames.isEmpty {
                Text(t.recording ? "Your line appears as you speak." : "Pitch is centered on your own voice; time is aligned to compare the shape.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.padding(16).background(RoundedRectangle(cornerRadius: 12).fill(Color.canvas))
        .accessibilityElement(children: .contain)
    }

    var syllables: some View {
        HStack(alignment: .center, spacing: 8) {
            ForEach(ex.units.indices, id: \.self) { i in
                let strong = ex.strong.contains(i), spans = trainingSpans(ex, skill)
                let position = t.recording ? t.seconds / t.targetDuration : t.playhead
                let active = (t.playing || t.recording) && position >= spans[i].0 && position < spans[i].1
                VStack(spacing: 12) {
                    Text(ex.units[i]).font(.system(size: strong ? 21 : 15, weight: strong ? .bold : .regular))
                        .foregroundStyle(strong ? Color.ink : Color.secondary).lineLimit(1).minimumScaleFactor(0.6)
                    Circle().fill(strong ? Color.violet : Color.line).frame(width: strong ? 13 : 7, height: strong ? 13 : 7)
                        .frame(height: 16).padding(6).background(Circle().fill(active ? Color.violet.opacity(0.13) : Color.clear))
                }.frame(maxWidth: .infinity)
            }
        }.padding(.vertical, 8)
    }

    var phraseGroups: some View {
        HStack(spacing: 8) {
            ForEach(ex.units.indices, id: \.self) { i in
                if i > 0 { Text("/").font(.system(size: 15)).foregroundStyle(Color.violet) }
                Text(ex.units[i]).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.horizontal, 8).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.violet.opacity(0.07)))
            }
        }
    }

    var contour: some View {
        let pitch = skill.usesPitch, userPitch = t.pitchCurve, userEnergy = t.energyCurve
        return Canvas { context, size in
            let rect = CGRect(x: 1, y: 8, width: size.width - 2, height: size.height - 16)
            for row in 0...4 {
                var line = Path(); let y = rect.minY + rect.height * Double(row) / 4
                line.move(to: CGPoint(x: rect.minX, y: y)); line.addLine(to: CGPoint(x: rect.maxX, y: y))
                context.stroke(line, with: .color(.line), lineWidth: 0.5)
            }
            if skill == .pauses {
                for fraction in ex.pauseAt {
                    let x = rect.minX + rect.width * fraction
                    var line = Path(); line.move(to: CGPoint(x: x, y: rect.minY)); line.addLine(to: CGPoint(x: x, y: rect.maxY))
                    context.stroke(line, with: .color(.violet.opacity(0.65)), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                }
                for (start, end) in t.pausePositions {
                    context.fill(Path(CGRect(x: rect.minX + start * rect.width, y: rect.minY, width: (end - start) * rect.width, height: rect.height)), with: .color(.pitch.opacity(0.12)))
                }
            }
            if !skill.selfReview && skill != .pauses {
                let target: [Double?] = (0...100).map { i in
                    let f = Double(i) / 100
                    return pitch ? ex.pattern.value(f) : trainingEnvelope(ex, skill, f)
                }
                context.stroke(curvePath(target, rect, pitch: pitch), with: .color(.violet.opacity(0.7)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [5, 5]))
            }
            let user: [Double?] = pitch ? userPitch : userEnergy.map { Optional($0) }
            if !user.isEmpty {
                let fraction = t.recording ? min(1, t.takeDuration / t.targetDuration) : 1
                let userRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height)
                context.stroke(curvePath(user, userRect, pitch: pitch), with: .color(.pitch), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            } else {
                context.draw(Text("Your line will appear here").font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: rect.midX, y: rect.maxY - 9))
            }
            if t.playing || t.playingTake {
                let x = rect.minX + rect.width * t.playhead
                var cursor = Path(); cursor.move(to: CGPoint(x: x, y: rect.minY)); cursor.addLine(to: CGPoint(x: x, y: rect.maxY))
                context.stroke(cursor, with: .color(.ink.opacity(0.25)), lineWidth: 1)
            }
        }
        .accessibilityLabel(pitch ? "Pitch movement: \(ex.pattern.cue). Purple dashed line is the target; blue is your voice." : "Voice energy timeline. Purple is the target; blue is your voice.\(skill == .pauses ? " Vertical dividers mark target pauses." : "")")
    }

    func curvePath(_ values: [Double?], _ rect: CGRect, pitch: Bool) -> Path {
        var path = Path(), connected = false
        for i in values.indices {
            guard let value = values[i] else { connected = false; continue }
            let normalized = pitch ? min(1, max(0, 0.5 - value / 12)) : 1 - min(1, max(0, value))
            let point = CGPoint(x: rect.minX + rect.width * Double(i) / Double(max(1, values.count - 1)), y: rect.minY + rect.height * normalized)
            if connected { path.addLine(to: point) } else { path.move(to: point) }
            connected = true
        }
        return path
    }

    var paceTimeline: some View {
        let duration = max(max(t.targetDuration, t.takeDuration), 0.1)
        return VStack(alignment: .leading, spacing: 14) {
            durationRow("Target", value: t.targetDuration, scale: duration, color: .violet)
            durationRow(t.recording ? "Your voice · live" : "Your speech", value: t.takeDuration, scale: duration, color: .pitch)
            Text(t.heardExample ? "Time from the example. Leading and trailing silence is trimmed from your take." : "Hear the target first to set its timing. Your take is timed from the first sound to the last.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(.vertical, 6)
    }

    func durationRow(_ label: String, value: Double, scale: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label).font(.system(size: 11, weight: .medium))
                Spacer()
                Text(value > 0 ? String(format: "%.1f seconds", value) : "Ready when you are").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.subtle)
                    Capsule().fill(color.opacity(0.7)).frame(width: g.size.width * min(1, value / scale))
                    if t.playing {
                        Circle().fill(Color.ink).frame(width: 8, height: 8).offset(x: max(0, g.size.width * t.playhead * t.targetDuration / scale - 4))
                    }
                }
            }.frame(height: 8)
        }
    }
}
