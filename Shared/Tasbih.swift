import Foundation

enum Dhikr: String, Codable, CaseIterable, Identifiable {
    case subhanAllah, alhamdulillah, allahuAkbar, laIlahaIllallah, astaghfirullah, salawat

    var id: String { rawValue }

    var arabic: String {
        switch self {
        case .subhanAllah: "سُبْحَانَ ٱللَّٰهِ"
        case .alhamdulillah: "ٱلْحَمْدُ لِلَّٰهِ"
        case .allahuAkbar: "ٱللَّٰهُ أَكْبَرُ"
        case .laIlahaIllallah: "لَا إِلَٰهَ إِلَّا ٱللَّٰهُ"
        case .astaghfirullah: "أَسْتَغْفِرُ ٱللَّٰهَ"
        case .salawat: "ٱللَّٰهُمَّ صَلِّ عَلَىٰ مُحَمَّدٍ"
        }
    }

    var transliteration: String {
        switch self {
        case .subhanAllah: "SubhanAllah"
        case .alhamdulillah: "Alhamdulillah"
        case .allahuAkbar: "Allahu Akbar"
        case .laIlahaIllallah: "La ilaha illallah"
        case .astaghfirullah: "Astaghfirullah"
        case .salawat: "Allahumma salli ala Muhammad"
        }
    }

    var meaning: String {
        switch self {
        case .subhanAllah: "Glory be to Allah"
        case .alhamdulillah: "All praise is due to Allah"
        case .allahuAkbar: "Allah is the Greatest"
        case .laIlahaIllallah: "There is no god but Allah"
        case .astaghfirullah: "I seek Allah's forgiveness"
        case .salawat: "O Allah, send blessings upon Muhammad"
        }
    }
}

/// The tasbih count lives in the App Group so the widget's button and the app stay in sync.
enum TasbihCounter {
    private enum Key {
        static let count = "tasbih.count"
        static let target = "tasbih.target"
        static let dhikr = "tasbih.dhikr"
        static let lifetime = "tasbih.lifetime"
    }

    private static var defaults: UserDefaults { AppGroup.defaults }

    static var count: Int {
        get { defaults.integer(forKey: Key.count) }
        set { defaults.set(newValue, forKey: Key.count) }
    }

    /// 0 means no target.
    static var target: Int {
        get { defaults.object(forKey: Key.target) as? Int ?? 33 }
        set { defaults.set(newValue, forKey: Key.target) }
    }

    static var dhikr: Dhikr {
        get { defaults.string(forKey: Key.dhikr).flatMap(Dhikr.init(rawValue:)) ?? .subhanAllah }
        set { defaults.set(newValue.rawValue, forKey: Key.dhikr) }
    }

    static var lifetimeCount: Int {
        get { defaults.integer(forKey: Key.lifetime) }
        set { defaults.set(newValue, forKey: Key.lifetime) }
    }

    @discardableResult
    static func increment() -> Int {
        count += 1
        lifetimeCount += 1
        return count
    }

    static func reset() { count = 0 }
}
