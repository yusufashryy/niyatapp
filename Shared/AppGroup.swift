import Foundation

/// Storage shared between the app and its widgets/extensions.
enum AppGroup {
    /// Comes from Info.plist, which gets it from `APP_GROUP_ID` in Config/Base.xcconfig.
    static let identifier: String =
        Bundle.main.object(forInfoDictionaryKey: "NiyatiAppGroup") as? String ?? "group.io.github.niyatiapp.niyati"

    /// Falls back to the app's own defaults if the App Group isn't set up
    /// (widgets then just show placeholder data).
    static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard
}

extension UserDefaults {
    func decoded<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func setEncoded<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            removeObject(forKey: key)
            return
        }
        set(data, forKey: key)
    }
}
