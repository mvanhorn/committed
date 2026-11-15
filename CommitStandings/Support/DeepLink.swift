import Foundation

/// Links into the iPhone app. `committed://board?window=<daily|weekly|monthly>` opens the Board on
/// that Window; Live rank's tap target uses the same URL. `committed://person/<login>` opens that
/// person's view, as a tapped pass notification does. Pure Foundation so the app, the Live
/// Activity extension, and the Mac tests can all share it.
enum DeepLink: Equatable, Sendable {
    /// Open the Board. A nil window keeps whichever Window is selected.
    case board(window: ContributionWindow?)
    /// Open someone's person view (a normalized GitHub login).
    case person(login: String)

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
            let parts = components.path.split(separator: "/")
            guard parts.count == 1, let login = UsernameNormalization.normalize(String(parts[0])) else { return nil }
            self = .person(login: login)
        default:
            return nil
        }
    }

    /// Where a tapped relay notification goes: a pass opens the rival's view. Nil for anything
    /// else (the app just opens).
    init?(notification userInfo: [AnyHashable: Any]) {
        guard userInfo["kind"] as? String == "pass", let raw = userInfo["login"] as? String,
              let login = UsernameNormalization.normalize(raw) else { return nil }
        self = .person(login: login)
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
        }
        return components.url!
    }
}
