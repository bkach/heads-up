import Foundation

enum MeetingLinkExtractor {
    private static let preferredHosts = [
        "meet.google.com",
        "zoom.us",
        "teams.microsoft.com",
        "teams.live.com",
        "app.slack.com",
        "whereby.com",
        "meet.jit.si",
        "webex.com",
        "chime.aws"
    ]

    static func extract(url: URL?, location: String?, notes: String?) -> URL? {
        let candidates = ([url?.absoluteString, location, notes].compactMap { $0 })
            .flatMap(extractURLs(from:))
            .filter(isSafeWebURL(_:))

        return candidates.first(where: isKnownMeetingURL(_:))
    }

    static func extractURLs(from text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: range).compactMap(\.url)
    }

    static func isSafeWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              url.host != nil else { return false }
        return true
    }

    static func isKnownMeetingURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return preferredHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}
