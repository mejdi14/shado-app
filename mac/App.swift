import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

private let backupRestored = Notification.Name("ShadowStudioBackupRestored")

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ n: Notification) { ServerManager.shared.stop() }
}

@main struct ShadowStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Window("Shadow Studio", id: "main") { RootView().frame(minWidth: 1100, minHeight: 680) }
            .defaultSize(width: 1320, height: 880)
            .windowStyle(.hiddenTitleBar)
        Settings { PracticeSettingsView() }
    }
}

private struct PracticeSettingsView: View {
    @ObservedObject private var server = ServerManager.shared
    @AppStorage(PracticeDefaults.modeKey) private var mode = PracticeDefaults.mode
    @AppStorage(PracticeDefaults.speedKey) private var speed = PracticeDefaults.speed
    @AppStorage(PracticeDefaults.loopingKey) private var looping = PracticeDefaults.looping
    @State private var microphoneStatus = MicrophoneProblem.status
    @State private var storageFolder: URL?
    @State private var storageUsage: LocalStorageUsage?
    @State private var storageRefresh = 0
    @State private var checkingStorage = true
    @State private var storageRevealFailed = false
    @State private var backupWorking = false
    @State private var backupMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Practice mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker("Playback speed", selection: Binding(
                    get: { PracticeDefaults.validSpeed(speed) },
                    set: { speed = $0 }
                )) {
                    ForEach(PracticeDefaults.speeds, id: \.self) { speed in
                        Text(speedLabel(speed)).tag(speed)
                    }
                }
                Toggle("Repeat phrase", isOn: $looping)
            } header: {
                Text("Practice defaults")
            } footer: {
                Text("Saved on this Mac. These defaults apply when you launch Shadow Studio or open a different session.")
            }
            Button("Reset Defaults") {
                mode = PracticeDefaults.mode
                speed = PracticeDefaults.speed
                looping = PracticeDefaults.looping
            }
            Section("Microphone") {
                LabeledContent("Access", value: microphoneStatus)
                HStack {
                    MicrophoneSettingsButton()
                    MicrophoneSettingsButton(showSound: true)
                    Button("Refresh Status") { microphoneStatus = MicrophoneProblem.status }
                }
            }
            Section("Local engine") {
                LabeledContent("Status", value: server.checkingStatus ? "Checking…" : server.connection.rawValue)
                ForEach(server.dependencyFacts) { fact in
                    LabeledContent(fact.label, value: fact.value)
                }
                if let message = server.setupHelp {
                    Text(message).foregroundStyle(.secondary)
                }
                HStack {
                    switch server.state {
                    case .failed:
                        Button("Try Again") { Task { await server.start() } }
                    case .ready:
                        Button("Refresh Status") { Task { await server.refreshStatus() } }
                            .disabled(server.checkingStatus)
                    case .starting:
                        ProgressView().controlSize(.small)
                    }
                    CopyEngineDiagnosticsButton(server: server)
                }
            }
            Section {
                if checkingStorage {
                    ProgressView("Checking storage…").controlSize(.small)
                } else if let storageUsage {
                    LabeledContent("Lesson files", value: ByteCountFormatter.string(fromByteCount: storageUsage.lessonBytes, countStyle: .file))
                    LabeledContent("Take files", value: ByteCountFormatter.string(fromByteCount: storageUsage.takeBytes, countStyle: .file))
                } else {
                    Text("Storage usage is unavailable.").foregroundStyle(.secondary)
                }
                HStack {
                    Button("Show Storage Folder", action: showStorageFolder)
                        .disabled(storageFolder == nil)
                    Button("Refresh Usage") { storageRefresh += 1 }
                        .disabled(checkingStorage)
                }
                if storageRevealFailed {
                    Text("The storage folder couldn’t be opened in Finder.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Local storage")
            } footer: {
                Text("Lesson files include saved session audio and metadata, including transcripts, edits and embedded feedback. Take files include recordings and separate take metadata. The guided sample counts toward usage. Temporary files, Voice Training progress and cached examples, and speech models are excluded. To free space, open a session and choose Delete session…")
            }
            Section("Local backup") {
                HStack {
                    Button("Export Backup…", action: exportBackup)
                        .disabled(backupWorking || backupAPI == nil || storageFolder == nil)
                    Button("Restore Backup…", action: restoreBackup)
                        .disabled(backupWorking || backupAPI == nil)
                    if backupWorking { ProgressView().controlSize(.small) }
                }
                Text("Back up sessions, takes, and Voice Training progress to a ZIP of up to 1 GiB. Restore skips existing session IDs, keeps your current guided sample while adding its matching backed-up takes, and adds any missing Voice Training completions.")
                    .foregroundStyle(.secondary)
                if let backupMessage { Text(backupMessage).textSelection(.enabled) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 600)
        .task { await server.refreshStatus() }
        .task(id: storageRefresh) { await refreshStorage() }
        .onAppear { microphoneStatus = MicrophoneProblem.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            microphoneStatus = MicrophoneProblem.status
        }
    }

    @MainActor private func refreshStorage() async {
        checkingStorage = true
        storageRevealFailed = false
        let folder = server.projectDir()?.appendingPathComponent("app.py").resolvingSymlinksInPath()
            .deletingLastPathComponent().appendingPathComponent("data", isDirectory: true)
        var usage: LocalStorageUsage?
        if let folder { usage = try? await LocalStorageUsage.read(from: folder) }
        guard !Task.isCancelled else { return }
        storageFolder = folder
        storageUsage = usage
        checkingStorage = false
    }

    private func showStorageFolder() {
        guard let storageFolder else { return }
        var isDirectory: ObjCBool = false
        storageRevealFailed = !FileManager.default.fileExists(atPath: storageFolder.path, isDirectory: &isDirectory)
            || !isDirectory.boolValue || !NSWorkspace.shared.open(storageFolder)
    }

    private var backupAPI: API? {
        if case .ready(let api) = server.state { return api }
        return nil
    }

    private func exportBackup() {
        guard !backupWorking, let api = backupAPI, let storage = storageFolder else { return }
        let picker = NSSavePanel()
        picker.allowedContentTypes = [.zip]
        picker.nameFieldStringValue = "Shadow Studio Backup.zip"
        picker.message = "Choose a new file outside the practice storage folder."
        picker.begin { reply in
            guard reply == .OK, let destination = picker.url else { return }
            runBackup {
                try await api.exportBackup(to: destination, storage: storage)
                return "Backup saved."
            }
        }
    }

    private func restoreBackup() {
        guard !backupWorking, let api = backupAPI else { return }
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.zip]
        picker.prompt = "Restore"
        picker.message = "Choose a Shadow Studio backup. Existing sessions and the current guided sample will be kept."
        picker.begin { reply in
            guard reply == .OK, let archive = picker.url else { return }
            runBackup {
                let result = try await api.get(BackupRestoreResult.self, "/api/backup/restore", method: "POST",
                                               contentType: "application/zip", file: archive, timeout: 600)
                storageRefresh += 1
                NotificationCenter.default.post(name: backupRestored, object: nil)
                return result.summary
            }
        }
    }

    private func runBackup(_ operation: @escaping @MainActor () async throws -> String) {
        guard !backupWorking else { return }
        backupWorking = true
        backupMessage = nil
        Task { @MainActor in
            defer { backupWorking = false }
            do { backupMessage = try await operation() }
            catch { backupMessage = error.localizedDescription }
        }
    }
}

private struct LocalStorageUsage: Sendable {
    var lessonBytes: Int64 = 0
    var takeBytes: Int64 = 0

    static func read(from folder: URL) async throws -> Self {
        let manager = FileManager.default
        var usage = Self()
        for session in try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            try Task.checkCancellation()
            guard isEngineID(session.lastPathComponent) else { continue }
            let directory = try session.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard directory.isDirectory == true, directory.isSymbolicLink == false,
                  let metadataBytes = try size(of: session.appendingPathComponent("lesson.json")) else { continue }
            usage.lessonBytes += metadataBytes
            for file in try manager.contentsOfDirectory(at: session, includingPropertiesForKeys: nil) {
                if file.lastPathComponent == "audio.wav" {
                    usage.lessonBytes += try size(of: file) ?? 0
                } else if ["wav", "json"].contains(file.pathExtension),
                          isEngineID(file.deletingPathExtension().lastPathComponent) {
                    usage.takeBytes += try size(of: file) ?? 0
                }
            }
        }
        return usage
    }

    private static func isEngineID(_ name: String) -> Bool {
        name.range(of: #"\A[0-9a-f]{32}\z"#, options: .regularExpression) != nil
    }

    private static func size(of file: URL) throws -> Int64? {
        do {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink == false else { return nil }
            return values.fileSize.map(Int64.init)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
    }
}

private struct CopyEngineDiagnosticsButton: View {
    @ObservedObject var server: ServerManager

    var body: some View {
        Button("Copy Diagnostics") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(server.diagnosticSummary, forType: .string)
        }
        .disabled(server.checkingStatus)
    }
}

struct RootView: View {
    @StateObject var server = ServerManager.shared
    var body: some View {
        Group {
            switch server.state {
            case .starting:
                VStack(spacing: 16) { ZStack { Orb(seed: "shadow studio", size: 56); ProgressView().controlSize(.small) }; Text("Starting Shadow Studio…").foregroundStyle(.secondary) }
            case .failed(let message):
                VStack(spacing: 16) {
                    Orb(seed: "shadow studio", size: 56)
                    Text(message).multilineTextAlignment(.center).frame(maxWidth: 460)
                    Button("Try again") { Task { await server.start() } }.buttonStyle(PillStyle(primary: true))
                    CopyEngineDiagnosticsButton(server: server)
                }.padding(40)
            case .ready(let api):
                StudioHost(api: api)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas.ignoresSafeArea())
        .task { await server.start() }
    }
}

@MainActor func announcePracticeStatus(_ message: String) {
    NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
        .announcement: message,
        .priority: NSAccessibilityPriorityLevel.medium.rawValue
    ])
}

struct StudioHost: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject var store: Store
    @StateObject var training: VoiceTrainingStore
    init(api: API) {
        _store = StateObject(wrappedValue: Store(api: api))
        _training = StateObject(wrappedValue: VoiceTrainingStore(api: api))
    }
    var body: some View {
        HStack(spacing: 0) {
            Sidebar().frame(width: 228).disabled(training.locked || training.saving).focusSection()
            Rectangle().fill(Color.line).frame(width: 1).ignoresSafeArea()
            ZStack {
                Group {
                    if store.showTraining { VoiceTrainingView() }
                    else if store.showLibrary { ScrollView { LibraryView() } }
                    else { StudioView() }
                }
                    .disabled(store.busy != nil)
                if let b = store.busy { BusyOverlay(busy: b) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.canvas.ignoresSafeArea())
            .overlay(alignment: .bottom) { if let t = store.toast { ToastView(text: t).padding(20).transition(.move(edge: .bottom).combined(with: .opacity)) } }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.toast)
            .onChange(of: store.toast) { message in
                if let message { announcePracticeStatus(message) }
            }
        }
        .font(.system(size: 13))
        .environmentObject(store)
        .environmentObject(training)
        .sheet(isPresented: $store.showImport) { ImportSheet().environmentObject(store) }
        .sheet(isPresented: $store.showEdit) { EditSheet().environmentObject(store) }
        .alert("Remove this session?", isPresented: $store.showDelete) {
            Button("Keep session", role: .cancel) {}
            Button("Delete session", role: .destructive) { Task { await store.deleteLesson() } }
        } message: { Text("This permanently deletes the session’s local folder, including its lesson audio, transcript, phrase edits, recordings, and feedback.") }
        .alert("Re-split this session?", isPresented: $store.showResplit) {
            Button("Keep phrases", role: .cancel) {}
            Button("Re-split phrases") { Task { await store.resplitLesson() } }
        } message: { Text("The audio is transcribed again. The new phrases start fresh at phrase one. You can restore the current phrases, edits, and progress. Each re-split replaces the previous restore point. Earlier takes stay in Take history.") }
        .alert("Restore the previous phrase version?", isPresented: $store.showUndoPhraseEdit) {
            Button("Cancel", role: .cancel) {}
            Button("Restore version") { Task { await store.restorePhrases(split: false) } }
        } message: {
            Text("Switch phrase \((store.lesson?.phraseEditIndex ?? 0) + 1) to its previous text, timing, and progress. You can switch back to this version. All takes stay in Take history.")
        }
        .alert("Restore the previous phrase set?", isPresented: $store.showRestorePhraseSplit) {
            Button("Cancel", role: .cancel) {}
            Button("Restore set") { Task { await store.restorePhrases(split: true) } }
        } message: { Text("Switch to the previous phrases, edits, and progress and start at phrase one. You can switch back to this set. All takes stay in Take history.") }
        .task { await store.start() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if store.recording { store.interruptRecording() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in
            store.interruptRecording()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            store.interruptRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange).receive(on: RunLoop.main)) { event in
            if let engine = store.engine, event.object as? AVAudioEngine === engine { store.interruptRecording() }
        }
        .onReceive(NotificationCenter.default.publisher(for: backupRestored)) { _ in
            Task {
                await store.guarded { try await store.refreshLibrary() }
                await training.loadProgress()
            }
        }
    }
}
