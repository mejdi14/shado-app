import Foundation
import AppKit
import CryptoKit

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

    func send(_ path: String, method: String = "GET", body: Data? = nil, contentType: String? = nil, file: URL? = nil) async throws -> Data {
        var req = URLRequest(url: URL(string: base.absoluteString + path)!)
        req.httpMethod = method; req.timeoutInterval = 120
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

    func get<T: Decodable>(_ type: T.Type, _ path: String, method: String = "GET", json: Any? = nil, body: Data? = nil, contentType: String? = nil, file: URL? = nil) async throws -> T {
        var payload = body, ctype = contentType
        if let json { payload = try JSONSerialization.data(withJSONObject: json); ctype = "application/json" }
        let data = try await send(path, method: method, body: payload, contentType: ctype, file: file)
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw AppError(message: "Shadow Studio couldn't read the server's reply. Restart the app and try again.") }
    }
}

@MainActor final class ServerManager: ObservableObject {
    static let shared = ServerManager()
    enum State { case starting, ready(API), failed(String) }
    @Published var state = State.starting
    var process: Process?
    var stopped = false

    func projectDir() -> URL? {
        var candidates = [Bundle.main.bundleURL.deletingLastPathComponent()]
        if let p = Bundle.main.object(forInfoDictionaryKey: "ShadowProjectDir") as? String { candidates.insert(URL(fileURLWithPath: p), at: 0) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("app.py").path) }
    }

    func serverUp(expected: String) async throws -> Bool {
        var req = URLRequest(url: base.appendingPathComponent("api/status"), cachePolicy: .reloadIgnoringLocalCacheData); req.timeoutInterval = 1.5
        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return false }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              String(data: data, encoding: .utf8)?.contains("\"local\":true") == true else {
            throw AppError(message: "Another app is using Shadow Studio's port (\(port)). Close it, then click Try again.")
        }
        guard http.value(forHTTPHeaderField: "X-Shadow-Engine") == expected else {
            throw AppError(message: "An outdated engine or another copy of Shadow Studio is still running. In its Terminal window, press Control-C to stop “Start Shadow Studio.command”, or quit the other Mac app. Then click Try again. Rebuilding alone does not restart a Terminal engine.")
        }
        return true
    }

    func start() async {
        state = .starting; stopped = false
        guard let dir = projectDir() else { return fail("Shadow Studio can't find its folder. Rebuild the app with “Build Mac App.command”.") }
        guard let source = try? Data(contentsOf: dir.appendingPathComponent("app.py")) else { return fail("Shadow Studio can't read its engine. Rebuild the app with “Build Mac App.command”.") }
        var signature = Data(dir.resolvingSymlinksInPath().path.utf8); signature.append(0); signature.append(source)
        let expected = SHA256.hash(data: signature).map { String(format: "%02x", $0) }.joined()
        let running: Bool
        do { running = try await serverUp(expected: expected) } catch { return fail(error.localizedDescription) }
        if !running {
            guard FileManager.default.isExecutableFile(atPath: dir.appendingPathComponent(".venv/bin/python").path) else { return fail("First-time setup hasn't been done yet. Open “Start Shadow Studio.command” once, then open this app again.") }
            guard ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"].contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return fail("FFmpeg is needed to read audio and video files. Install it with Homebrew: brew install ffmpeg") }
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
            p.terminationHandler = { _ in Task { @MainActor in ServerManager.shared.stopped = true } }
            do { try p.run() } catch { return fail("Shadow Studio couldn't start its local server.") }
            process = p
            var waited = 0.0
            while true {
                do { if try await serverUp(expected: expected) { break } } catch { return fail(error.localizedDescription) }
                if stopped { return fail("The local server stopped while starting. Details are in ~/Library/Logs/Shadow Studio.log") }
                if waited > 120 { return fail("The local server is taking too long to start. Details are in ~/Library/Logs/Shadow Studio.log") }
                try? await Task.sleep(nanoseconds: 250_000_000); waited += 0.25
            }
        }
        guard let token = await API.fetchToken() else { return fail("Shadow Studio couldn't connect to its local server. Quit and open the app again.") }
        state = .ready(API(token: token))
    }

    func fail(_ text: String) { state = .failed(text) }
    func stop() { process?.terminate() }
}
