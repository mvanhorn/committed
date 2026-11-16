import Foundation
import Testing
@testable import CommitStandingsiOS

/// About you's lines under each switch (#124 review): when a record or the streak reminder arrives
/// follows Delivery, the evening summary's time included. Expected strings written out by hand.
struct AboutYouSectionTests {
    private func choices(_ delivery: NotificationPreferences.Delivery, quietHours: NotificationPreferences.QuietHours? = .init(start: "22:00", end: "08:00")) -> NotificationPreferences {
        var choices = NotificationPreferences()
        choices.delivery = delivery
        choices.quietHours = quietHours
        return choices
    }

    @Test func inTheSummaryTheyArriveAt9PM() {
        let summary = choices(.summary)
        #expect(AboutYouSection.recordsDetail(summary)
            == "When you set a new best day, best week or longest streak, in the summary at 9 PM.")
        #expect(AboutYouSection.streakReminderDetail(summary)
            == "In the summary at 9 PM, when your streak is 2 days or more and you haven't contributed yet today.")
    }

    @Test func theSummaryMovesUpToQuietHoursAsDeliverySays() {
        let early = choices(.summary, quietHours: .init(start: "20:30", end: "07:00"))
        let clock = DeliverySection.summaryClock(early)
        #expect(clock != "9 PM")
        #expect(AboutYouSection.recordsDetail(early).hasSuffix("in the summary at \(clock)."))
        #expect(DeliverySection.footer(early, on: true).contains("at \(clock), when quiet hours start"))
    }

    @Test func rightAwayTheyArriveAsTheyHappen() {
        let immediate = choices(.immediate)
        #expect(AboutYouSection.recordsDetail(immediate)
            == "When you set a new best day, best week or longest streak. One set during quiet hours comes when they end.")
        #expect(AboutYouSection.streakReminderDetail(immediate)
            == "At 8 PM, or an hour before quiet hours if that's earlier, when your streak is 2 days or more and you haven't contributed yet today.")
        #expect(AboutYouSection.recordsDetail(choices(.immediate, quietHours: nil))
            == "When you set a new best day, best week or longest streak.")
    }
}
