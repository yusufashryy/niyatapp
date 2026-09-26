import Foundation

/// A reading (qira'ah / riwayah) of the Qur'an. Only readings with an
/// authenticated digital text are offered; add new ones by adding a case here
/// and an edition below. Never derive one reading from another.
enum Riwayah: String, CaseIterable, Identifiable, Codable {
    case hafs, warsh, qalun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hafs: "Hafs ʿan ʿAsim"
        case .warsh: "Warsh ʿan Nafiʿ"
        case .qalun: "Qalun ʿan Nafiʿ"
        }
    }

    var arabicTitle: String {
        switch self {
        case .hafs: "حفص عن عاصم"
        case .warsh: "ورش عن نافع"
        case .qalun: "قالون عن نافع"
        }
    }

    var detail: String {
        switch self {
        case .hafs: "The most widely read riwayah worldwide. 6,236 ayat (Kufan count)."
        case .warsh: "Read across North and West Africa. 6,214 ayat (Madinan count)."
        case .qalun: "Read in Libya, Tunisia and parts of West Africa. 6,214 ayat (Madinan count)."
        }
    }

    /// Verse-by-verse recitation audio exists only for Hafs in our verified source.
    /// For other readings audio is switched off rather than mismatched.
    var hasVerseAudio: Bool { self == .hafs }

    var editions: [QuranEdition] { QuranEdition.allCases.filter { $0.riwayah == self } }
}

/// One verified Qur'an text: a riwayah written in a particular script.
enum QuranEdition: String, CaseIterable, Identifiable, Codable {
    case uthmani, uthmaniMinimal, imlaei, warsh, qalun

    var id: String { rawValue }

    var riwayah: Riwayah {
        switch self {
        case .uthmani, .uthmaniMinimal, .imlaei: .hafs
        case .warsh: .warsh
        case .qalun: .qalun
        }
    }

    var title: String {
        switch self {
        case .uthmani: "Uthmani"
        case .uthmaniMinimal: "Uthmani, fewer marks"
        case .imlaei: "Imlaei (modern spelling)"
        case .warsh: "Warsh (Maghribi dabt)"
        case .qalun: "Qalun (Maghribi dabt)"
        }
    }

    var detail: String {
        switch self {
        case .uthmani: "The Madinah-style Uthmani script with full marks."
        case .uthmaniMinimal: "Uthmani script with only the essential marks, for experienced readers."
        case .imlaei: "The same text in everyday Arabic spelling, fully vocalised."
        case .warsh: "The Warsh text as printed in Maghribi mushafs."
        case .qalun: "The Qalun text as printed in Maghribi mushafs."
        }
    }

    /// Bundled file (in Resources/Quran), without ".json".
    var fileName: String {
        switch self {
        case .uthmani: "quran-uthmani"
        case .uthmaniMinimal: "quran-uthmani-min"
        case .imlaei: "quran-imlaei"
        case .warsh: "quran-warsh"
        case .qalun: "quran-qalun"
        }
    }

    /// SHA-256 of the bundled file, as published with the source dataset.
    var sha256: String {
        switch self {
        case .uthmani: "adaebb377c60eba1bab6ef652959c7a0b4ccb4d0ca42145945c14ecdbeb4b761"
        case .uthmaniMinimal: "ea44601cb1c17c03461daa1d2c37328778312007f449938e9038f9dbd010015a"
        case .imlaei: "703246a73a0a3d57f721b02e3edad9a2ee6831b79f49ffb9513ddfe99a65b801"
        case .warsh: "f9d98e5089add2626479936ca48b8904508f208a5350855aa00ee8aa7b2b61aa"
        case .qalun: "ece0a2b0efe44d496211c595d0a34f495413bc93f78fba8095a666e2048d1303"
        }
    }

    var source: String {
        switch riwayah {
        case .hafs: "Tanzil Project (tanzil.net), CC BY 3.0, used verbatim."
        case .warsh, .qalun: "Qur'anpedia.net (qurānpedia) mushaf dump version 2026-09-18, from the KFGQPC printed mushaf. Credited per the Qur'anpedia data licence."
        }
    }

    /// Verses carry their own Hafs verse numbers (the Madinan count splits and
    /// joins some verses differently), used to line up translations and bookmarks.
    var isMappedToHafs: Bool { riwayah != .hafs }

    static let `default` = QuranEdition.uthmani
}
