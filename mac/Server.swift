import Foundation
import AppKit
import CryptoKit
import Darwin

let port = ProcessInfo.processInfo.environment["SHADOW_PORT"] ?? "8765"
let base = URL(string: "http://127.0.0.1:\(port)")!
let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Shadow Studio.log")

struct AppError: LocalizedError {
    let message: String
    var statusCode: Int? = nil
    var errorDescription: String? { message }
}

final class API {
    let token: String
    init(token: String) { self.token = token }

    static func fetchToken() async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: base), let html = String(data: data, encoding: .utf8),
              let r = html.range(of: #"name="shadow-token" content="[^"]+""#, options: .regularExpression) else { return nil }
        return String(html[r]).components(separatedBy: "\"").dropLast().last
    }

    func send(_ path: String, method: String = "GET", body: Data? = nil, contentType: String? = nil, file: URL? = nil, timeout: TimeInterval = 120) async throws -> Data {
        var req = URLRequest(url: URL(string: base.absoluteString + path)!)
        req.httpMethod = method; req.timeoutInterval = timeout
        req.setValue(token, forHTTPHeaderField: "X-Shadow-Token")
        if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let data: Data, response: URLResponse
        do {
            if let file { (data, response) = try await URLSession.shared.upload(for: req, fromFile: file) }
            else if let body { (data, response) = try await URLSession.shared.upload(for: req, from: body) }
            else { (data, response) = try await URLSession.shared.data(for: req) }
        } catch { throw AppError(message: "Shadow Studio's local server isn't responding. Quit and open the app again.") }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw AppError(message: detail ?? "Something went wrong. Please try again.", statusCode: http.statusCode)
        }
        return data
    }

    func get<T: Decodable>(_ type: T.Type, _ path: String, method: String = "GET", json: Any? = nil, body: Data? = nil, contentType: String? = nil, file: URL? = nil, timeout: TimeInterval = 120) async throws -> T {
        var payload = body, ctype = contentType
        if let json { payload = try JSONSerialization.data(withJSONObject: json); ctype = "application/json" }
        let data = try await send(path, method: method, body: payload, contentType: ctype, file: file, timeout: timeout)
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw AppError(message: "Shadow Studio couldn't read the server's reply. Restart the app and try again.") }
    }

    func exportBackup(to destination: URL, storage: URL) async throws {
        var req = URLRequest(url: URL(string: base.absoluteString + "/api/backup/export")!, timeoutInterval: 600)
        req.httpMethod = "POST"
        req.setValue(token, forHTTPHeaderField: "X-Shadow-Token")
        let (download, response) = try await URLSession.shared.download(for: req)
        defer { try? FileManager.default.removeItem(at: download) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.mimeType == "application/zip" else {
            let reply = try? FileHandle(forReadingFrom: download)
            defer { try? reply?.close() }
            let data = try reply?.read(upToCount: 4096) ?? Data()
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw AppError(message: detail ?? "Shadow Studio couldn’t create the backup.")
        }
        try Self.saveBackup(download, to: destination, storage: storage)
    }

    private static func saveBackup(_ download: URL, to destination: URL, storage: URL) throws {
        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        let folderError = AppError(message: "Choose a local folder outside Shadow Studio’s data folder, with no linked folders in its path.")
        var practiceDirectory = stat()
        guard destination.isFileURL, destination.path.hasPrefix("/"),
              lstat(storage.path, &practiceDirectory) == 0,
              practiceDirectory.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw folderError }
        var parent = open("/", flags)
        guard parent >= 0 else { throw folderError }
        defer { close(parent) }
        for component in destination.deletingLastPathComponent().pathComponents.dropFirst() {
            guard component != ".", component != ".." else { throw folderError }
            let next = openat(parent, component, flags)
            guard next >= 0 else { throw folderError }
            close(parent)
            parent = next
            var info = stat()
            guard fstat(parent, &info) == 0,
                  info.st_dev != practiceDirectory.st_dev || info.st_ino != practiceDirectory.st_ino else { throw folderError }
        }

        let name = destination.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.utf8.contains(0) else { throw folderError }
        let fileError = AppError(message: "The backup couldn’t be saved. Check available space and choose a new file in a writable folder.")
        let temporary = ".shadow-backup-" + UUID().uuidString
        let input = open(download.path, O_RDONLY | O_NOFOLLOW)
        guard input >= 0 else { throw fileError }
        defer { close(input) }
        let output = openat(parent, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard output >= 0 else { throw fileError }
        defer { close(output); unlinkat(parent, temporary, 0) }
        guard fcopyfile(input, output, nil, copyfile_flags_t(COPYFILE_DATA)) == 0, fsync(output) == 0 else { throw fileError }
        // The directory descriptor stays fixed and the final name must be new.
        guard renameatx_np(parent, temporary, parent, name, UInt32(RENAME_EXCL)) == 0 else {
            if errno == EEXIST { throw AppError(message: "A file already has this name. Choose a new name for the backup.") }
            throw fileError
        }
    }
}

@MainActor final class ServerManager: ObservableObject {
    static let shared = ServerManager()
    enum State { case starting, ready(API), failed(String) }
    @Published var state = State.starting
    enum EngineConnection: String {
        case unchecked = "Not checked"
        case offline = "No response"
        case otherService = "Unexpected response"
        case stale = "Different engine build"
        case matching = "Matching engine build"
        case tokenUnavailable = "App connection failed"
        case projectUnavailable = "Engine files unavailable"
        case setupRequired = "First-time setup required"
        case missingFFmpeg = "FFmpeg missing"
    }
    @Published private(set) var connection = EngineConnection.unchecked
    @Published private(set) var engineStatus: EngineStatus?
    @Published private(set) var checkingStatus = false
    private var expectedSignature: String?
    private var starting = false
    private var process: Process?

    func projectDir() -> URL? {
        var candidates = [Bundle.main.bundleURL.deletingLastPathComponent()]
        if let p = Bundle.main.object(forInfoDictionaryKey: "ShadowProjectDir") as? String { candidates.insert(URL(fileURLWithPath: p), at: 0) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("app.py").path) }
    }

    private func serverUp(expected: String) async throws -> Bool {
        var req = URLRequest(url: base.appendingPathComponent("api/status"), cachePolicy: .reloadIgnoringLocalCacheData); req.timeoutInterval = 1.5
        let reply = try? await URLSession.shared.data(for: req)
        try Task.checkCancellation()
        engineStatus = nil
        guard let (data, response) = reply else {
            connection = .offline
            return false
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let status = try? JSONDecoder().decode(EngineStatus.self, from: data), status.local else {
            connection = .otherService
            throw AppError(message: "Another app is using Shadow Studio's port (\(port)). Close it, then click Try again.")
        }
        guard http.value(forHTTPHeaderField: "X-Shadow-Engine") == expected else {
            connection = .stale
            throw AppError(message: "An outdated engine or another copy of Shadow Studio is still running. In its Terminal window, press Control-C to stop “Start Shadow Studio.command”, or quit the other Mac app. Then click Try again. Rebuilding alone does not restart a Terminal engine.")
        }
        engineStatus = status
        connection = .matching
        return true
    }

    func refreshStatus() async {
        guard case .ready = state, let expectedSignature, !checkingStatus else { return }
        checkingStatus = true
        defer { checkingStatus = false }
        _ = try? await serverUp(expected: expectedSignature)
    }

    func start() async {
        guard !starting else { return }
        starting = true
        defer { starting = false }
        state = .starting
        connection = .unchecked
        engineStatus = nil
        guard let dir = projectDir() else { return fail("Shadow Studio can't find its folder. Rebuild the app with “Build Mac App.command”.", connection: .projectUnavailable) }
        guard let source = try? Data(contentsOf: dir.appendingPathComponent("app.py")) else { return fail("Shadow Studio can't read its engine. Rebuild the app with “Build Mac App.command”.", connection: .projectUnavailable) }
        var signature = Data(dir.resolvingSymlinksInPath().path.utf8); signature.append(0); signature.append(source)
        let expected = SHA256.hash(data: signature).map { String(format: "%02x", $0) }.joined()
        expectedSignature = expected
        let running: Bool
        do { running = try await serverUp(expected: expected) } catch { return fail(error.localizedDescription) }
        if !running {
            if process?.isRunning != true {
                guard FileManager.default.isExecutableFile(atPath: dir.appendingPathComponent(".venv/bin/python").path) else { return fail("First-time setup hasn't been done yet. Open “Start Shadow Studio.command” once, then click Try Again.", connection: .setupRequired) }
                guard ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"].contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return fail("FFmpeg is needed to read audio and video files. Install it with Homebrew using brew install ffmpeg, then click Try Again.", connection: .missingFFmpeg) }
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-c", "[[ -x /usr/bin/say ]] && .venv/bin/python create_sample.py; exec .venv/bin/python app.py"]
                p.currentDirectoryURL = dir
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
                env["HF_HOME"] = dir.appendingPathComponent("data/models").path
                env["SHADOW_PORT"] = port
                p.environment = env
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
                if let log = try? FileHandle(forWritingTo: logURL) { p.standardOutput = log; p.standardError = log }
                do { try p.run() } catch { return fail("Shadow Studio couldn't start its local server.") }
                process = p
            }
            var waited = 0.0
            while true {
                do { if try await serverUp(expected: expected) { break } } catch { return fail(error.localizedDescription) }
                if process?.isRunning != true { return fail("The local server stopped while starting. Details are in ~/Library/Logs/Shadow Studio.log") }
                if waited > 120 { return fail("The local server is taking too long to start. Details are in ~/Library/Logs/Shadow Studio.log") }
                try? await Task.sleep(nanoseconds: 250_000_000); waited += 0.25
            }
        }
        guard let token = await API.fetchToken() else {
            connection = .tokenUnavailable
            return fail("Shadow Studio couldn't connect to its local server. Click Try Again, or quit and reopen Shadow Studio if the problem persists.")
        }
        state = .ready(API(token: token))
    }

    struct DependencyFact: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    var dependencyFacts: [DependencyFact] {
        let ffmpeg = connection == .missingFFmpeg ? false : engineStatus?.ffmpeg
        return [
            DependencyFact(label: "FFmpeg", value: ffmpeg.map { $0 ? "Available" : "Missing" } ?? "Unknown"),
            DependencyFact(label: "Speech model", value: engineStatus?.modelReady.map { $0 ? "Loaded" : "Not loaded" } ?? "Unknown"),
            DependencyFact(label: "ElevenLabs CLI", value: engineStatus?.elevenLabsCLI.map { $0 ? "Available" : "Missing" } ?? "Unknown")
        ]
    }

    var diagnosticSummary: String {
        (["Shadow Studio engine diagnostics", "Engine status: \(connection.rawValue)"] +
            dependencyFacts.map { "\($0.label): \($0.value)" }).joined(separator: "\n")
    }

    var setupHelp: String? {
        if case .failed(let message) = state { return message }
        guard case .ready = state else { return nil }
        switch connection {
        case .offline:
            return "Quit and reopen Shadow Studio to reconnect to the local engine."
        case .otherService:
            return "Close the app using Shadow Studio’s port, then reopen Shadow Studio."
        case .stale:
            return "Stop the older engine with Control-C in its Terminal window, or quit the other copy of Shadow Studio. Then reopen this app."
        default:
            let steps = [
                engineStatus?.ffmpeg == false ? "Install FFmpeg with brew install ffmpeg, then refresh status." : nil,
                engineStatus?.modelReady == false ? "The first transcription loads the speech model and downloads it if it isn’t cached. Refresh status after it finishes." : nil,
                engineStatus?.elevenLabsCLI == false ? "For PDF import, install the optional ElevenLabs CLI and run elevenlabs auth login in Terminal." : nil
            ].compactMap { $0 }
            return steps.isEmpty ? nil : steps.joined(separator: "\n\n")
        }
    }

    private func fail(_ text: String, connection: EngineConnection? = nil) {
        if let connection { self.connection = connection }
        state = .failed(text)
    }
    func stop() { process?.terminate() }
}
