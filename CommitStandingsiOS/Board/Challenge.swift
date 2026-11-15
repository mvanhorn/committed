import Foundation

/// A challenge to someone on your board: your race with them over the Board's 30 days, told in
/// your voice, for the story image and the message that carries the link to their side of it
/// (gitcommitted.app/vs/<you>/<friend>, the challenge page). Only the 30-day totals decide the
/// words, as on the page (`site/lib/challenge.ts`): equal totals are "Dead level", where the Board
/// would count the tie for you.
struct Challenge: Equatable, Sendable {
    /// Who's ahead, in your voice.
    enum Variant: Equatable, Sendable, CustomStringConvertible {
        /// You're ahead: "I'm 12 ahead of you, ezra-q."
        case ahead
        /// They are: "You're 12 ahead of me, ezra-q. Not for long."
        case behind
        /// Equal totals: "Dead level, ezra-q."
        case level

        var description: String {
            switch self {
            case .ahead: "ahead"
            case .behind: "behind"
            case .level: "level"
            }
        }
    }

    /// Your login, as GitHub shows it.
    let you: String
    /// Theirs.
    let friend: String
    let yourTotal: Int
    let theirTotal: Int
    /// Numbers are grouped for this locale: "1,204".
    var locale: Locale = .current

    static let eyebrow = "A challenge · \(ContributionWindow.monthly.shortTitle)"
    static let prompt = "Think you can catch me?"
    static let site = "gitcommitted.app"

    var variant: Variant {
        yourTotal > theirTotal ? .ahead : theirTotal > yourTotal ? .behind : .level
    }

    var gap: Int { abs(yourTotal - theirTotal) }

    /// The story's headline.
    var headline: String {
        [headlineLead, taunt].compactMap { $0 }.joined(separator: " ")
    }

    /// The headline up to the taunt: "You're 12 ahead of me, ezra-q."
    var headlineLead: String {
        switch variant {
        case .ahead: "I’m \(gapText) ahead of you, \(friend)."
        case .behind: "You’re \(gapText) ahead of me, \(friend)."
        case .level: "Dead level, \(friend)."
        }
    }

    /// "Not for long.", when they're ahead.
    var taunt: String? {
        variant == .behind ? "Not for long." : nil
    }

    /// The message beside the image, with the link: "ezra-q, I'm 12 ahead of you on Committed: …".
    var message: String {
        switch variant {
        case .ahead: "\(friend), I’m \(gapText) ahead of you on Committed: \(url.absoluteString)"
        case .behind: "\(friend), you’re \(gapText) ahead of me on Committed. Not for long: \(url.absoluteString)"
        case .level: "\(friend), we’re dead level on Committed: \(url.absoluteString)"
        }
    }

    /// The challenge page, you first. GitHub logins are case-insensitive; the page reads them
    /// lowercased.
    var url: URL {
        URL(string: "https://\(linkText)")!
    }

    /// The link as the story's footer prints it: "gitcommitted.app/vs/addisonk/ezra-q".
    var linkText: String {
        "\(Self.site)/vs/\(Self.pathLogin(you))/\(Self.pathLogin(friend))"
    }

    /// The gap as the headline prints it: "1,204".
    var gapText: String {
        gap.formatted(.number.locale(locale))
    }

    /// A login as a path segment. GitHub logins are letters, digits and hyphens, so lowercasing is
    /// enough; anything else is escaped rather than trusted.
    private static func pathLogin(_ login: String) -> String {
        login.lowercased().addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-"))) ?? login
    }
}

extension Challenge {
    /// Your race with `person` as a challenge: nil on your own view and until both your counts
    /// have loaded (the race is missing then, never zeros).
    init?(you: String, person: PersonSummary, locale: Locale = .current) {
        guard !person.isYou, let race = person.race else { return nil }
        self.init(you: you, friend: person.login, yourTotal: race.yourTotal, theirTotal: race.theirTotal,
                  locale: locale)
    }
}
