import SwiftUI

/// A tajweed rule that can be coloured in the text.
///
/// Colours follow the scheme used in colour-coded (Dar al-Maarifah style)
/// masahif: blues for madd, orange for ghunnah, purple for ikhfa, greens for
/// idgham, red for qalqalah and grey for letters that are not pronounced.
enum TajweedRule: String, CaseIterable, Identifiable {
    case ghunnah
    case ikhfa
    case ikhfaShafawi = "ikhfa_shafawi"
    case iqlab
    case idghamGhunnah = "idghaam_ghunnah"
    case idghamNoGhunnah = "idghaam_no_ghunnah"
    case idghamShafawi = "idghaam_shafawi"
    case idghamMutajanisayn = "idghaam_mutajanisayn"
    case idghamMutaqaribayn = "idghaam_mutaqaribayn"
    case qalqalah
    case madd2 = "madd_2"
    case madd246 = "madd_246"
    case maddMuttasil = "madd_muttasil"
    case maddMunfasil = "madd_munfasil"
    case madd6 = "madd_6"
    case hamzatWasl = "hamzat_wasl"
    case lamShamsiyyah = "lam_shamsiyyah"
    case silent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ghunnah: "Ghunnah"
        case .ikhfa: "Ikhfa"
        case .ikhfaShafawi: "Ikhfa shafawi"
        case .iqlab: "Iqlab"
        case .idghamGhunnah: "Idgham with ghunnah"
        case .idghamNoGhunnah: "Idgham without ghunnah"
        case .idghamShafawi: "Idgham shafawi"
        case .idghamMutajanisayn: "Idgham mutajanisayn"
        case .idghamMutaqaribayn: "Idgham mutaqaribayn"
        case .qalqalah: "Qalqalah"
        case .madd2: "Madd: 2 counts"
        case .madd246: "Madd: 2, 4 or 6 counts"
        case .maddMuttasil: "Madd muttasil: 4–5 counts"
        case .maddMunfasil: "Madd munfasil: 4–5 counts"
        case .madd6: "Madd lazim: 6 counts"
        case .hamzatWasl: "Hamzat al-wasl"
        case .lamShamsiyyah: "Lam shamsiyyah"
        case .silent: "Silent letter"
        }
    }

    var explanation: String {
        switch self {
        case .ghunnah: "A nasal sound held for two counts, on noon or meem with shaddah."
        case .ikhfa: "Noon sakinah or tanween before one of 15 letters: hidden, with ghunnah."
        case .ikhfaShafawi: "Meem sakinah before baa: hidden, with ghunnah."
        case .iqlab: "Noon sakinah or tanween before baa turns into a hidden meem, with ghunnah."
        case .idghamGhunnah: "Noon sakinah or tanween merged into ي ن م و, with ghunnah."
        case .idghamNoGhunnah: "Noon sakinah or tanween merged into ل or ر, without ghunnah."
        case .idghamShafawi: "Meem sakinah merged into a following meem, with ghunnah."
        case .idghamMutajanisayn: "Two letters from the same place of articulation: the first merges into the second."
        case .idghamMutaqaribayn: "Two letters from close places of articulation: the first merges into the second."
        case .qalqalah: "An echoing bounce on ق ط ب ج د when they have sukoon."
        case .madd2: "Natural lengthening for two counts."
        case .madd246: "Lengthening of two, four or six counts when stopping (al-'arid, al-leen)."
        case .maddMuttasil: "A madd letter followed by hamzah in the same word: four or five counts."
        case .maddMunfasil: "A madd letter at the end of a word, followed by hamzah in the next: four or five counts."
        case .madd6: "Necessary lengthening of six counts."
        case .hamzatWasl: "Not pronounced when continuing from the previous word."
        case .lamShamsiyyah: "The lam of al- is silent and merges into the next (sun) letter."
        case .silent: "Written but not pronounced."
        }
    }

    /// Colour on light (paper) pages.
    var lightColor: Color {
        switch self {
        case .ghunnah: Color(hex: 0xE8730C)
        case .ikhfa: Color(hex: 0x8E1FA3)
        case .ikhfaShafawi: Color(hex: 0xC2189F)
        case .iqlab: Color(hex: 0x0E9FD8)
        case .idghamGhunnah: Color(hex: 0x14866D)
        case .idghamNoGhunnah: Color(hex: 0x1F8A1C)
        case .idghamShafawi: Color(hex: 0x4E9D00)
        case .idghamMutajanisayn, .idghamMutaqaribayn: Color(hex: 0x8A8A8A)
        case .qalqalah: Color(hex: 0xD0101B)
        case .madd2: Color(hex: 0x4B7BF0)
        case .madd246: Color(hex: 0x3A4DE0)
        case .maddMuttasil: Color(hex: 0x2138B8)
        case .maddMunfasil: Color(hex: 0x2A5CC9)
        case .madd6: Color(hex: 0x0B1A8C)
        case .hamzatWasl, .lamShamsiyyah, .silent: Color(hex: 0x9A9A9A)
        }
    }

    /// Brighter versions that stay readable on dark pages.
    var darkColor: Color {
        switch self {
        case .ghunnah: Color(hex: 0xFF9A45)
        case .ikhfa: Color(hex: 0xD27CF0)
        case .ikhfaShafawi: Color(hex: 0xFF7AD9)
        case .iqlab: Color(hex: 0x5ED3FF)
        case .idghamGhunnah: Color(hex: 0x4ED7B5)
        case .idghamNoGhunnah: Color(hex: 0x6FDB5E)
        case .idghamShafawi: Color(hex: 0xA6E04A)
        case .idghamMutajanisayn, .idghamMutaqaribayn: Color(hex: 0xB5B5B5)
        case .qalqalah: Color(hex: 0xFF5A5F)
        case .madd2: Color(hex: 0x8FB0FF)
        case .madd246: Color(hex: 0x7C8CFF)
        case .maddMuttasil: Color(hex: 0x6F82FF)
        case .maddMunfasil: Color(hex: 0x74A2FF)
        case .madd6: Color(hex: 0xA99BFF)
        case .hamzatWasl, .lamShamsiyyah, .silent: Color(hex: 0x8C8C8C)
        }
    }

    /// With Increase Contrast on, colours are deeper on paper and brighter on
    /// dark pages.
    func color(dark: Bool, highContrast: Bool = false) -> Color {
        let base = dark ? darkColor : lightColor
        return highContrast ? base.mix(with: dark ? .white : .black, by: 0.3) : base
    }

    /// Rules shown together in the colour guide.
    enum Group: String, CaseIterable, Identifiable {
        case madd = "Madd (lengthening)"
        case ghunnah = "Ghunnah and ikhfa"
        case idgham = "Idgham (merging)"
        case qalqalah = "Qalqalah"
        case silent = "Not pronounced"
        var id: String { rawValue }
    }

    var group: Group {
        switch self {
        case .madd2, .madd246, .maddMuttasil, .maddMunfasil, .madd6: .madd
        case .ghunnah, .ikhfa, .ikhfaShafawi, .iqlab: .ghunnah
        case .idghamGhunnah, .idghamNoGhunnah, .idghamShafawi, .idghamMutajanisayn, .idghamMutaqaribayn: .idgham
        case .qalqalah: .qalqalah
        case .hamzatWasl, .lamShamsiyyah, .silent: .silent
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Tajweed marks for the Hafs Uthmani text, from cpfair/quran-tajweed
/// (CC BY 4.0). Offsets are Unicode code points into the verse text exactly as
/// bundled (see scripts/generate_tajweed.py and docs/SOURCES.md).
@MainActor
@Observable
final class TajweedStore {
    static let shared = TajweedStore()

    struct Mark {
        let rule: TajweedRule
        let range: Range<Int>
    }

    private(set) var isLoaded = false
    @ObservationIgnored private var marks: [String: (length: Int, marks: [Mark])] = [:]

    private init() {}

    func load() async {
        guard !isLoaded else { return }
        let loaded = await Task.detached(priority: .userInitiated) { Self.read() }.value
        marks = loaded
        isLoaded = true
    }

    private nonisolated static func read() -> [String: (length: Int, marks: [Mark])] {
        struct File: Decodable {
            let rules: [String]
            let ayat: [String: [Int]]
        }
        guard let url = Bundle.main.url(forResource: "tajweed-hafs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [:] }
        let rules = file.rules.map(TajweedRule.init(rawValue:))
        var result: [String: (length: Int, marks: [Mark])] = [:]
        for (key, flat) in file.ayat {
            guard let length = flat.first else { continue }
            var marks: [Mark] = []
            var i = 1
            while i + 2 < flat.count {
                if let rule = rules[flat[i]] { marks.append(Mark(rule: rule, range: flat[i + 1]..<flat[i + 2])) }
                i += 3
            }
            result[key] = (length, marks)
        }
        return result
    }

    /// Marks for a verse as displayed. `displayed` may be the verse with the
    /// Bismillah removed from its start; marks are shifted to match.
    func marks(surah: Int, verse: Int, displayed: String) -> [Mark] {
        guard let entry = marks["\(surah):\(verse)"] else { return [] }
        let shift = entry.length - displayed.unicodeScalars.count
        guard shift >= 0 else { return [] }
        return entry.marks.compactMap { mark in
            let lower = mark.range.lowerBound - shift, upper = mark.range.upperBound - shift
            guard upper > 0 else { return nil }
            return Mark(rule: mark.rule, range: max(lower, 0)..<upper)
        }
    }
}

/// Qur'an › Settings › Tajweed colour guide.
struct TajweedGuideView: View {
    @AppStorage("quran.tajweed") private var tajweedOn = true

    var body: some View {
        List {
            Section {
                Toggle("Show tajweed colours", isOn: $tajweedOn)
            } footer: {
                Text("Colours the letters where a tajweed rule applies, in the Uthmani script (Hafs). Rules from the Quran Tajweed project (CC BY 4.0), built from the Dar al-Maarifah colour-coded mushaf and ReciteQuran.com.")
            }
            ForEach(TajweedRule.Group.allCases) { group in
                Section(group.rawValue) {
                    ForEach(TajweedRule.allCases.filter { $0.group == group }) { rule in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(rule.darkColor)
                                .frame(width: 14, height: 14)
                                .padding(.top, 4)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rule.title).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(rule.darkColor)
                                Text(rule.explanation).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .niyatBackground()
        .navigationTitle("Tajweed colours")
        .navigationBarTitleDisplayMode(.inline)
    }
}
