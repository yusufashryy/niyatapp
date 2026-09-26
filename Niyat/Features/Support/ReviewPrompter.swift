import Foundation
import Observation

/// Decides when to ask for an App Store rating and when to offer feedback.
///
/// Ratings use Apple's own prompt (iOS shows it at most three times a year and
/// may skip it). We only ask after a happy moment (finishing the Qur'an goal
/// or logging all five prayers), once the app has been used for a few days,
/// and at most once per app version. Feedback is offered once, after about
/// ten days.
@MainActor
@Observable
final class ReviewPrompter {
    static let shared = ReviewPrompter()

    /// Set to true when the system rating prompt should be shown.
    var askForReview = false
    /// Set to true when the one-time "send feedback" alert should be shown.
    var offerFeedback = false

    private enum Key {
        static let firstLaunch = "review.firstLaunch"
        static let happyMoments = "review.happyMoments"
        static let lastPromptedVersion = "review.lastPromptedVersion"
        static let feedbackOffered = "review.feedbackOffered"
    }

    private let defaults = UserDefaults.standard
    private var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    private init() {}

    private var daysSinceFirstLaunch: Int {
        guard let first = defaults.object(forKey: Key.firstLaunch) as? Date else { return 0 }
        return Calendar.current.dateComponents([.day], from: first, to: .now).day ?? 0
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Call when the main screen appears.
    func appOpened() {
        if defaults.object(forKey: Key.firstLaunch) == nil {
            defaults.set(Date.now, forKey: Key.firstLaunch)
        }
        guard !isDemo, !defaults.bool(forKey: Key.feedbackOffered), daysSinceFirstLaunch >= 10 else { return }
        defaults.set(true, forKey: Key.feedbackOffered)
        offerFeedback = true
    }

    /// Call after something good happens: the Qur'an goal is reached, or a
    /// day's five prayers are all logged.
    func recordHappyMoment() {
        let count = defaults.integer(forKey: Key.happyMoments) + 1
        defaults.set(count, forKey: Key.happyMoments)
        guard !isDemo, count >= 4, daysSinceFirstLaunch >= 3,
              defaults.string(forKey: Key.lastPromptedVersion) != appVersion else { return }
        defaults.set(appVersion, forKey: Key.lastPromptedVersion)
        askForReview = true
    }

    /// App Store "write a review" page, once the app is published and
    /// `APP_STORE_ID` is set in Config/Base.xcconfig.
    static var writeReviewURL: URL? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "NiyatAppStoreID") as? String,
              !id.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
    }
}
