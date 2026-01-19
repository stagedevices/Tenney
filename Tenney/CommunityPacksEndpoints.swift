import Foundation

enum CommunityPacksEndpoints {
    static let rawBase = URL(string: "https://raw.githubusercontent.com/stagedevices/tenney-scales/main/")!
    static let cdnBase = URL(string: "https://cdn.jsdelivr.net/gh/stagedevices/tenney-scales@main/")!

    static let indexPath = "INDEX.json"
    static let submitURL = URL(string: "https://tenneyapp.com/community")!
    static let issuesURL = URL(string: "https://github.com/stagedevices/tenney-scales/issues/new?template=pack_submission.yml")!

    static func url(base: URL, path: String) -> URL {
        var url = base
        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        return url
    }
}
