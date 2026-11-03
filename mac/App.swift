import SwiftUI

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

struct StudioHost: View {
    @StateObject var store: Store
    @StateObject var training: VoiceTrainingStore
    init(api: API) {
        _store = StateObject(wrappedValue: Store(api: api))
        _training = StateObject(wrappedValue: VoiceTrainingStore(api: api))
    }
    var body: some View {
        HStack(spacing: 0) {
            Sidebar().frame(width: 228).disabled(training.locked || training.saving)
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
            .animation(.easeInOut(duration: 0.2), value: store.toast)
        }
        .font(.system(size: 13))
        .environmentObject(store)
        .environmentObject(training)
        .sheet(isPresented: $store.showImport) { ImportSheet().environmentObject(store) }
        .sheet(isPresented: $store.showEdit) { EditSheet().environmentObject(store) }
        .alert("Remove this session?", isPresented: $store.showDelete) {
            Button("Keep session", role: .cancel) {}
            Button("Delete session", role: .destructive) { Task { await store.deleteLesson() } }
        } message: { Text("Its imported audio, recordings, and feedback will be deleted from this Mac.") }
        .alert("Re-split this session?", isPresented: $store.showResplit) {
            Button("Keep phrases", role: .cancel) {}
            Button("Re-split phrases") { Task { await store.resplitLesson() } }
        } message: { Text("The audio is transcribed again and divided into new phrases. Your phrase edits and feedback for this session will be cleared.") }
        .task { await store.start() }
    }
}
