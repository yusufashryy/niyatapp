import Foundation

/// The optional recitation check: Quran Muaalem, an AI model on Niyat's
/// server, listens to each part recited between pauses and points out letters,
/// vowels and tajweed to check (see server/README.md).
///
/// Off until the reader turns it on after reading the AI notice, and only for
/// the Hafs Uthmani texts the server knows.
enum RecitationCheckSettings {
    static let enabledKey = "quran.recitationCheck.enabled"
    /// The AI notice has been shown (the licence requires it before first use).
    static let noticeSeenKey = "quran.recitationCheck.noticeSeen.v1"

    /// Set in Config/Local.xcconfig (RECITATION_SERVER), e.g. "1-2-3-4.sslip.io".
    static let server: URL? = serverURL(from: Bundle.main.object(forInfoDictionaryKey: "NiyatRecitationServer") as? String)
    static let key: String? = {
        let value = (Bundle.main.object(forInfoDictionaryKey: "NiyatRecitationKey") as? String)?
            .trimmingCharacters(in: .whitespaces)
        return value?.isEmpty == false ? value : nil
    }()

    /// This build has a server to talk to.
    static var isAvailable: Bool { server != nil && key != nil }

    static func supports(_ edition: QuranEdition) -> Bool {
        edition == .uthmani || edition == .uthmaniMinimal
    }

    /// On, and usable for this reading.
    static func isOn(for edition: QuranEdition) -> Bool {
        isAvailable && supports(edition) && isEnabled
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) && noticeSeen }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var noticeSeen: Bool {
        get { UserDefaults.standard.bool(forKey: noticeSeenKey) }
        set { UserDefaults.standard.set(newValue, forKey: noticeSeenKey) }
    }

    /// "host[:port][/path]" from the build settings. Plain http only for this
    /// Mac or the local network (trying the server out); HTTPS for the rest.
    static func serverURL(from value: String?) -> URL? {
        guard var text = value?.trimmingCharacters(in: .whitespaces), !text.isEmpty, !text.hasPrefix("$(") else {
            return nil
        }
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        let host = String(text.prefix { $0 != ":" && $0 != "/" }).lowercased()
        guard !host.isEmpty else { return nil }
        let local = host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local")
        return URL(string: "\(local ? "http" : "https")://\(text)")
    }
}
