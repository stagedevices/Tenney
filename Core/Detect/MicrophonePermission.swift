import Foundation
import AVFoundation
#if canImport(AVFAudio)
import AVFAudio
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

enum MicrophonePermission {

    enum Status { case undetermined, denied, granted }

    static func status() -> Status {
        #if os(iOS) || targetEnvironment(macCatalyst)
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:      return .granted
        case .denied:       return .denied
        case .undetermined: return .undetermined
        @unknown default:   return .denied
        }
        #else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:   return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default:   return .denied
        }
        #endif
    }

    /// Ensures mic permission; completion always called on main.
    static func ensure(_ completion: @escaping (Bool) -> Void) {
        let finish: (Bool) -> Void = { ok in
            if Thread.isMainThread { completion(ok) }
            else { DispatchQueue.main.async { completion(ok) } }
        }

        switch status() {
        case .granted:
            finish(true)

        case .denied:
            finish(false)

        case .undetermined:
            #if os(iOS) || targetEnvironment(macCatalyst)
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                finish(granted)
            }
            #else
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                finish(granted)
            }
            #endif
        }
    }

    /// Convenience wrapper (matches your existing call sites).
    static func ensureGranted(_ onGranted: @escaping () -> Void,
                              onDenied: @escaping () -> Void) {
        ensure { ok in ok ? onGranted() : onDenied() }
    }

    static func openAppSettings() {
        #if os(iOS) || targetEnvironment(macCatalyst)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #elseif os(macOS)
        // Best-effort deep link (may change across macOS versions)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}
