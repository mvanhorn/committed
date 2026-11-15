import Foundation

/// Links into the iPhone app. `committed://board?window=<daily|weekly|monthly>` opens the Board on
/// that Window; Live rank's tap target uses the same URL. `committed://person/<login>` opens that
/// person's view, as a tapped pass notification does; `committed://challenge/<login>` opens it and
/// presents the Challenge share, as a pass notification's Share your race does. Pure Foundation so
/// the app, the Live Activity extension, and the Mac tests can all share it.
enum DeepLink: Equatable, Sendable {
    /// Open the Board. A nil window keeps whichever Window is selected.
    case board(window: ContributionWindow?)
    /// Open someone's person view (a normalized GitHub login).
    case person(login: String)
    /// Open someone's person view and present their Challenge share (a normalized GitHub login).
    case challenge(login: String)

    static let scheme = "committed"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch components.host?.lowercased() {
        case "board":
            guard components.path.isEmpty || components.path == "/" else { return nil }
            let window = components.queryItems?
                .first(where: { $0.name == "window" })?.value
                .flatMap(ContributionWindow.init(rawValue:))
            self = .board(window: window)
        case "person":
            guard let login = Self.login(inPath: components.path) else { return nil }
            self = .person(login: login)
        case "challenge":
            guard let login = Self.login(inPath: components.path) else { return nil }
            self = .challenge(login: login)
        default:
            return nil
        }
    }

    /// A pass notification's category and its two actions (#137). iPhone registers them at launch;
    /// relay passes carry the category.
    static let passCategory = "PASS"
    static let shareRaceAction = "SHARE_RACE"
    static let openBoardAction = "OPEN_BOARD"
    /// iOS's identifier for a tap on the notification itself (`UNNotificationDefaultActionIdentifier`).
    static let bodyTapAction = "com.apple.UNNotificationDefaultActionIdentifier"

    /// Where a tapped relay notification goes. A pass: the body opens the rival's view, Share your
    /// race opens it with their Challenge share, Open Board opens the Board. A close call (#132) opens
    /// that person's view; a record (#134), which carries your own login, opens your own view; a
    /// result (#131, a daily result or last week's final) opens the Board. Nil for anything else
    /// (another kind, a dismissal, an unknown action), and the app just opens.
    init?(notification userInfo: [AnyHashable: Any], action: String = Self.bodyTapAction) {
        let kind = userInfo["kind"] as? String
        // A result has no actions either: tapping it opens the Board.
        if kind == "result" {
            guard action == Self.bodyTapAction else { return nil }
            self = .board(window: nil)
            return
        }
        let login = (userInfo["login"] as? String).flatMap(UsernameNormalization.normalize)
        // Close calls, records and streak reminders have no actions: tapping one opens the view of
        // the login it names (yours, for records and streak reminders).
        if kind == "closeCall" || kind == "record" || kind == "streakReminder" {
            guard action == Self.bodyTapAction, let login else { return nil }
            self = .person(login: login)
            return
        }
        guard kind == "pass" else { return nil }
        switch action {
        case Self.bodyTapAction:
            guard let login else { return nil }
            self = .person(login: login)
        case Self.shareRaceAction:
            guard let login else { return nil }
            self = .challenge(login: login)
        case Self.openBoardAction:
            self = .board(window: nil)
        default:
            return nil
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .board(let window):
            components.host = "board"
            if let window { components.queryItems = [URLQueryItem(name: "window", value: window.rawValue)] }
        case .person(let login):
            components.host = "person"
            components.path = "/" + login
        case .challenge(let login):
            components.host = "challenge"
            components.path = "/" + login
        }
        return components.url!
    }

    /// The one login in a `/<login>` path, normalized.
    private static func login(inPath path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count == 1 else { return nil }
        return UsernameNormalization.normalize(String(parts[0]))
    }
}
