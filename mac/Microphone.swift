import AppKit
import AVFoundation
import SwiftUI

enum MicrophoneProblem: Error {
    case denied, restricted, unavailable, failed

    static var status: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: return "Permission requested when you first record"
        case .authorized: return hasInput ? "Allowed" : "Allowed · no microphone detected"
        case .denied: return "Denied"
        case .restricted: return "Restricted by macOS"
        @unknown default: return "Unknown"
        }
    }

    private static var hasInput: Bool { AVCaptureDevice.default(for: .audio) != nil }

    @MainActor static func checkInput() async throws {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw AVCaptureDevice.authorizationStatus(for: .audio) == .restricted ? Self.restricted : Self.denied
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            guard hasInput else { throw Self.unavailable }
        case .denied: throw Self.denied
        case .restricted: throw Self.restricted
        default: throw Self.failed
        }
    }

    var message: String {
        switch self {
        case .denied: return "Allow Shadow Studio in System Settings → Privacy & Security → Microphone, then retry recording."
        case .restricted: return "macOS restricts microphone access. Check Screen Time or device management restrictions, then retry recording."
        case .unavailable: return "No microphone input is available. Connect or select one in System Settings → Sound → Input, then retry recording."
        case .failed: return "The microphone couldn’t start. Check System Settings → Sound → Input, then retry recording."
        }
    }
}

struct MicrophoneSettingsButton: View {
    var showSound = false

    var body: some View {
        Button(showSound ? "Open Sound Settings" : "Open Microphone Settings") {
            let pane = showSound ? "com.apple.Sound-Settings.extension?input" : "com.apple.preference.security?Privacy_Microphone"
            guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
            if !NSWorkspace.shared.open(url),
               let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
                NSWorkspace.shared.open(app)
            }
        }
    }
}

struct MicrophoneRecoveryView: View {
    let problem: MicrophoneProblem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(problem.message, systemImage: "exclamationmark.circle")
                .font(.callout).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if problem != .restricted {
                MicrophoneSettingsButton(showSound: problem != .denied)
                    .buttonStyle(PillStyle(compact: true))
            }
        }
    }
}
