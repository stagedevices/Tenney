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
}
