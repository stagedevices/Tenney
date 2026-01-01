//
//  MicPermission.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 1/1/26.
//


// MicPermission.swift
import SwiftUI
import AVFAudio

@MainActor
enum MicPermission {
    static func ensureGranted(_ onGranted: @escaping @MainActor () -> Void,
                              onDenied: @escaping @MainActor () -> Void) {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            onGranted()

        case .undetermined:
            // MUST be requested on main
            session.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    granted ? onGranted() : onDenied()
                }
            }

        case .denied:
            onDenied()

        @unknown default:
            onDenied()
        }
    }

    static func openAppSettings() {
        #if canImport(UIKit)
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        #endif
    }
    /// Convenience wrapper that matches your "granted/denied" call sites.
        static func ensureGranted(_ onGranted: @escaping () -> Void,
                                  onDenied: @escaping () -> Void) {
            ensure { ok in
                if ok { onGranted() } else { onDenied() }
            }
        }
    
        /// Deep-link into the app’s Settings page (iOS / Catalyst).
        static func openAppSettings() {
            #if os(iOS) || targetEnvironment(macCatalyst)
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
            #endif
        }
}
