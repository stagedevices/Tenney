//
//  MicrophonePermissiojn.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/1/25.
//

import Foundation
import AVFoundation

enum MicrophonePermission {
    /// Ensures mic permission; calls back on the main thread.
    static func ensure(_ completion: @escaping (Bool) -> Void) {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            DispatchQueue.main.async { completion(true) }
        case .denied:
            DispatchQueue.main.async { completion(false) }
        case .undetermined:
            session.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        @unknown default:
            DispatchQueue.main.async { completion(false) }
        }
    }
}
