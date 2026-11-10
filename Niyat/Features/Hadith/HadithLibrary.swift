import Foundation
import Observation

/// How strong a hadith's chain is, as its grading scholar judged it. Niyat only
/// carries the two grades scholars accept as proof (scripts/build_hadith.py).
enum HadithLevel: String, Decodable {
    case sahih
    case hasan

    var title: String {
        switch self {
        case .sahih: "Sahih"
        case .hasan: "Hasan"
        }
    }

    var meaning: String {
        switch self {
        case .sahih: "Authentic: a sound, unbroken chain of trustworthy narrators."
        case .hasan: "Good: accepted as proof, with narrators slightly less precise than Sahih."
        }
    }
}

/// One hadith from HadeethEnc, exactly as published.
struct Hadith: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let text: String
    let arabic: String
    /// Who recorded it, e.g. "Narrated by Bukhari & Muslim".
    let source: String
    /// The grading in the encyclopedia's words, e.g. "Authentic hadith".
    let grade: String
    let level: HadithLevel
    let explanation: String
    let lessons: [String]
    let topics: [Int]
}

/// A subject heading, e.g. "Virtues and Manners" › "Heart-Softeners".
struct HadithTopic: Identifiable, Hashable {
    let id: Int
    /// 0 for the top level.
    let parent: Int
    let title: String
    /// Hadiths filed directly under this topic.
    let count: Int
}

/// The bundled file, as `scripts/build_hadith.py` writes it.
struct HadithFile: Decodable {
    let version: String
    let topics: [HadithTopic]
    let hadiths: [Hadith]

    private enum CodingKeys: String, CodingKey { case version, topics, hadiths }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version)
        hadiths = try c.decode([Hadith].self, forKey: .hadiths)
        var list = try c.nestedUnkeyedContainer(forKey: .topics)
        var topics: [HadithTopic] = []
        while !list.isAtEnd {
            var row = try list.nestedUnkeyedContainer()
            topics.append(HadithTopic(id: try row.decode(Int.self), parent: try row.decode(Int.self),
                                      title: try row.decode(String.self), count: try row.decode(Int.self)))
        }
        self.topics = topics
    }

    /// Reads a `.hadith` file: raw-DEFLATE-compressed JSON.
    static func decode(compressed data: Data) throws -> HadithFile {
        let json = try (data as NSData).decompressed(using: .zlib) as Data
        return try JSONDecoder().decode(HadithFile.self, from: json)
    }
}

/// An everyday situation to look up, e.g. "Feeling angry". Its words are what
/// the search looks for (any of them).
struct HadithScenario: Identifiable, Hashable {
    let title: String
    let icon: String
    let words: [String]
    var id: String { title }

    static let all: [HadithScenario] = [
        HadithScenario(title: "Anger", icon: "flame", words: ["anger", "angry", "rage", "temper"]),
        HadithScenario(title: "Parents", icon: "figure.2.and.child.holdinghands", words: ["parent", "mother", "father"]),
        HadithScenario(title: "Patience", icon: "hourglass", words: ["patience", "patient", "affliction", "calamity"]),
        HadithScenario(title: "Grief", icon: "cloud.rain", words: ["grief", "sad", "sorrow", "distress", "worry", "anxiety"]),
        HadithScenario(title: "Debt", icon: "creditcard", words: ["debt", "loan", "borrow", "owe"]),
        HadithScenario(title: "Marriage", icon: "heart", words: ["marriage", "marry", "wife", "husband", "spouse"]),
        HadithScenario(title: "Neighbours", icon: "house", words: ["neighbor", "neighbour"]),
        HadithScenario(title: "Honesty", icon: "checkmark.seal", words: ["truth", "honest", "lie", "lying", "liar"]),
        HadithScenario(title: "Kindness", icon: "hand.raised", words: ["kind", "gentle", "mercy", "merciful"]),
        HadithScenario(title: "Charity", icon: "gift", words: ["charity", "sadaqah", "give", "spend"]),
        HadithScenario(title: "Prayer", icon: "moon.stars", words: ["prayer", "pray", "salah"]),
        HadithScenario(title: "Fasting", icon: "sunset", words: ["fast", "fasting", "ramadan"]),
        HadithScenario(title: "Repentance", icon: "arrow.uturn.backward", words: ["repent", "repentance", "forgive", "forgiveness"]),
        HadithScenario(title: "Illness", icon: "cross.case", words: ["sick", "illness", "disease", "ill"]),
        HadithScenario(title: "Death", icon: "leaf", words: ["death", "dead", "funeral", "grave"]),
        HadithScenario(title: "Knowledge", icon: "book", words: ["knowledge", "learn", "scholar"])
    ]
}

/// Finds hadiths by words or by situation. Pure, so it's tested.
struct HadithIndex {
    let file: HadithFile
    private let topicsByID: [Int: HadithTopic]
    /// Hadiths under each topic, counting the topics below it.
    private let countsByTopic: [Int: Int]
    /// Searchable text of each hadith, folded, by field weight.
    private let fields: [[(text: String, weight: Int)]]

    init(_ file: HadithFile) {
        self.file = file
        let topics = Dictionary(uniqueKeysWithValues: file.topics.map { ($0.id, $0) })
        topicsByID = topics
        // Each hadith counts once for every topic above the ones it's filed under.
        var counts: [Int: Int] = [:]
        for hadith in file.hadiths {
            var seen: Set<Int> = []
            for filed in hadith.topics {
                var id = filed
                while id != 0, !seen.contains(id), let topic = topics[id] {
                    seen.insert(id)
                    id = topic.parent
                }
            }
            for id in seen { counts[id, default: 0] += 1 }
        }
        countsByTopic = counts
        fields = file.hadiths.map { hadith in
            let topicTitles = hadith.topics.compactMap { topics[$0]?.title }.joined(separator: " ")
            return [(Self.fold(hadith.title), 5), (Self.fold(topicTitles), 4),
                    (Self.fold(hadith.text), 2), (Self.fold(hadith.lessons.joined(separator: " ")), 2),
                    (Self.fold(hadith.explanation), 1)]
        }
    }

    var hadiths: [Hadith] { file.hadiths }

    /// The top-level topics, in the encyclopedia's order.
    var rootTopics: [HadithTopic] { file.topics.filter { $0.parent == 0 } }

    func subtopics(of topic: HadithTopic) -> [HadithTopic] { file.topics.filter { $0.parent == topic.id } }

    func topic(_ id: Int) -> HadithTopic? { topicsByID[id] }

    /// How many hadiths are under the topic or any topic below it (worked out once).
    func count(in topic: HadithTopic) -> Int { countsByTopic[topic.id] ?? 0 }

    /// Hadiths filed under the topic or any topic below it.
    func hadiths(in topic: HadithTopic) -> [Hadith] {
        var ids: Set<Int> = [topic.id]
        var frontier = [topic.id]
        while let next = frontier.popLast() {
            for child in file.topics where child.parent == next && !ids.contains(child.id) {
                ids.insert(child.id)
                frontier.append(child.id)
            }
        }
        return file.hadiths.filter { !ids.isDisjoint(with: $0.topics) }
    }

    /// The hadith for a day of the year, the same for everyone that day.
    func hadithOfTheDay(_ date: Date = .now, calendar: Calendar = .current) -> Hadith? {
        guard !file.hadiths.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return file.hadiths[day % file.hadiths.count]
    }

    /// Hadiths matching every word typed (each word may start a longer one:
    /// "pray" finds "prayer"), best first. If nothing has all of them, those
    /// with most of them.
    func search(_ query: String, limit: Int = 200) -> [Hadith] {
        let words = Self.words(in: query)
        guard !words.isEmpty else { return [] }
        return rank(groups: words.map { [$0] }, requireAll: true, limit: limit)
    }

    /// Hadiths about a situation: any of its words, best first.
    func search(_ scenario: HadithScenario, limit: Int = 200) -> [Hadith] {
        rank(groups: [scenario.words.map(Self.fold)], requireAll: true, limit: limit)
    }

    private func rank(groups: [[String]], requireAll: Bool, limit: Int) -> [Hadith] {
        var scored: [(index: Int, matched: Int, score: Int)] = []
        for (index, fields) in fields.enumerated() {
            var matched = 0, score = 0
            for group in groups {
                let best = fields.map { field in group.contains { Self.contains(field.text, word: $0) } ? field.weight : 0 }.max() ?? 0
                if best > 0 { matched += 1; score += best }
            }
            if matched > 0 { scored.append((index, matched, score)) }
        }
        let all = scored.filter { $0.matched == groups.count }
        let chosen = all.isEmpty && requireAll && groups.count > 1 ? scored : all
        return chosen
            .sorted { ($0.matched, $0.score, -$0.index) > ($1.matched, $1.score, -$1.index) }
            .prefix(limit)
            .map { file.hadiths[$0.index] }
    }

    // MARK: Text

    private static let stopWords: Set<String> = ["a", "an", "the", "of", "and", "or", "to", "in", "on", "for", "is",
                                                 "about", "what", "when", "how", "my", "i", "me", "with", "do", "does"]

    static func words(in query: String) -> [String] {
        fold(query).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { !stopWords.contains($0) }
    }

    /// Lower case, without accents or the encyclopedia's ‘ʿ’ marks, so "Abū" matches "abu".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
            .replacing(/[‘’ʿʾ'`]/, with: "")
    }

    /// Whether a word in `text` starts with `word`.
    static func contains(_ text: String, word: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: word, range: searchRange) {
            if found.lowerBound == text.startIndex || !text[text.index(before: found.lowerBound)].isLetter { return true }
            searchRange = found.upperBound..<text.endIndex
        }
        return false
    }
}

/// Loads the hadiths once, off the main thread, and keeps them.
@MainActor @Observable
final class HadithLibrary {
    static let shared = HadithLibrary()

    enum LoadError: LocalizedError {
        case missing
        var errorDescription: String? { "The hadiths aren't in the app. Try reinstalling Niyat." }
    }

    private(set) var index: HadithIndex?
    private(set) var loadError: String?
    private var loading: Task<HadithIndex, Error>?

    /// The hadiths, loading them the first time.
    @discardableResult
    func load() async -> HadithIndex? {
        if let index { return index }
        guard let url = Bundle.main.url(forResource: "hadith-en", withExtension: "hadith") else {
            loadError = LoadError.missing.localizedDescription
            return nil
        }
        let task = loading ?? Task.detached(priority: .utility) {
            HadithIndex(try HadithFile.decode(compressed: try Data(contentsOf: url)))
        }
        loading = task
        do {
            let loaded = try await task.value
            index = loaded
            loadError = nil
            return loaded
        } catch {
            loading = nil
            loadError = "Couldn't open the hadiths. Please try again."
            return nil
        }
    }
}

/// Hadiths you've saved to come back to, kept on this iPhone.
@MainActor @Observable
final class SavedHadiths {
    static let shared = SavedHadiths()
    private static let key = "hadith.saved"

    /// Newest first.
    private(set) var ids: [Int]

    private init() {
        ids = UserDefaults.standard.array(forKey: Self.key) as? [Int] ?? []
    }

    func contains(_ hadith: Hadith) -> Bool { ids.contains(hadith.id) }

    func toggle(_ hadith: Hadith) {
        ids = Self.toggled(hadith.id, in: ids)
        UserDefaults.standard.set(ids, forKey: Self.key)
    }

    /// Adds the id at the front, or removes it if it's there. Pure, so it's tested.
    nonisolated static func toggled(_ id: Int, in ids: [Int]) -> [Int] {
        ids.contains(id) ? ids.filter { $0 != id } : [id] + ids
    }

    /// The saved hadiths that are still in the library, newest first.
    func hadiths(in index: HadithIndex) -> [Hadith] {
        let byID = Dictionary(uniqueKeysWithValues: index.hadiths.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }
}
