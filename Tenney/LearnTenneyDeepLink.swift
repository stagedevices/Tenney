import Foundation

enum LearnTenneyDeepLinkDestination: String, Sendable {
    case libraryHome
    case communityPacks
    case builderHome
    case communityPackSubmission

    static func from(_ notification: Notification) -> LearnTenneyDeepLinkDestination? {
        guard let raw = notification.userInfo?[LearnTenneyDeepLinkPayload.destinationKey] as? String else { return nil }
        return LearnTenneyDeepLinkDestination(rawValue: raw)
    }
}

enum LearnTenneyDeepLinkPayload {
    static let destinationKey = "destination"
}

extension Notification.Name {
    static let tenneyLearnDeepLink = Notification.Name("tenney.learn.deepLink")
}
