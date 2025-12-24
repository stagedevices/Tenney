//
//  ScalaExporter.swift
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 12/22/25.
//


//
//  ScalaExporter.swift
//  Tenney
//

import Foundation
import UIKit

enum ScalaExporter {

    /// Writes `.scl` + `.kbm` into `temporaryDirectory` and returns the URLs.
    static func writeTempFiles(baseName: String,
                              sclText: String,
                              kbmText: String) throws -> [URL] {
        let dir = FileManager.default.temporaryDirectory
        let safeBase = baseName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        let sclURL = dir.appendingPathComponent("\(safeBase).scl")
        let kbmURL = dir.appendingPathComponent("\(safeBase).kbm")

        try sclText.write(to: sclURL, atomically: true, encoding: .utf8)
        try kbmText.write(to: kbmURL, atomically: true, encoding: .utf8)

        return [sclURL, kbmURL]
    }

    /// Presents a share sheet for the given URLs.
    static func presentShare(urls: [URL]) {
        let controller = UIActivityViewController(activityItems: urls,
                                                  applicationActivities: nil)

        guard let root = UIApplication.shared.firstKeyWindow?.rootViewController else { return }

        // find top-most presented VC
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(controller, animated: true)
    }
}

extension UIApplication {
    var firstKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
