import Foundation
import Observation

/// Sends each part recited between pauses to the recitation check and puts
/// its marks on the words. While it works, its marks replace the speech
/// recogniser's (which only turns words green as you go); if the server
/// can't be reached, live recitation falls back to the recogniser's marks.
@MainActor
@Observable
final class RecitationChecker {
    static let shared = RecitationChecker()

    enum Health: Equatable {
        case ready
        /// No connection or no answer: marks come from speech recognition for now.
        case offline
        /// This build's server address or key is wrong.
        case notSetUp
    }

    /// The check is used in this session.
    private(set) var isActive = false
    /// Recordings sent and not answered yet.
    private(set) var pending = 0
    private(set) var health = Health.ready
    /// Goes up when a word was clearly different (for the haptic and notice).
    private(set) var mistakeNotice = 0

    /// Its own marks are on the words (the recogniser's are held back).
    var marksWords: Bool { isActive && health == .ready }

    @ObservationIgnored private(set) var notes: [WordID: [RecitationCheckAnswer.Note]] = [:]
    /// Words the check has judged; the recogniser leaves them alone.
    @ObservationIgnored private(set) var checked: Set<WordID> = []
    /// The last word the check heard: the next recording starts after it.
    @ObservationIgnored private(set) var lastEnd: WordID?
    @ObservationIgnored private var client: RecitationCheckClient?
    @ObservationIgnored private var session = 0

    private init() {}

    func begin(edition: QuranEdition) {
        isActive = RecitationCheckSettings.isOn(for: edition)
        guard isActive, let server = RecitationCheckSettings.server, let key = RecitationCheckSettings.key else {
            isActive = false
            return
        }
        client = RecitationCheckClient(server: server, key: key)
        if health == .offline { health = .ready }
    }

    /// Listening stopped. Recordings already sent still get their marks.
    func end() {
        isActive = false
    }

    func clear() {
        session += 1
        notes = [:]
        checked = []
        lastEnd = nil
        pending = 0
    }

    func submit(_ samples: [Int16], at place: WordID) {
        guard isActive, health != .notSetUp, let client else { return }
        let session = session
        let wav = WAVFile.data(samples: samples)
        let at = RecitationCheckAnswer.Place(surah: place.surah, ayah: place.verse, word: place.index)
        pending += 1
        Task {
            defer { if session == self.session { pending = max(pending - 1, 0) } }
            do {
                let answer = try await Self.send(wav, at: at, with: client)
                guard session == self.session else { return }
                health = .ready
                if answer.status == .notFound {
                    // Not the text around the place: maybe another surah.
                    let found = try await client.find(wav: wav)
                    guard session == self.session else { return }
                    moveIfElsewhere(found)
                } else {
                    apply(answer)
                }
            } catch {
                switch error as? RecitationCheckError {
                case .notSetUp: health = .notSetUp
                case .offline: health = .offline
                // Busy twice, or this recording wasn't accepted: skip it.
                case .busy, .rejected, nil: break
                }
            }
        }
    }

    /// One retry when the server is busy.
    private nonisolated static func send(_ wav: Data, at place: RecitationCheckAnswer.Place,
                                         with client: RecitationCheckClient) async throws -> RecitationCheckAnswer {
        do {
            return try await client.check(wav: wav, at: place)
        } catch RecitationCheckError.busy {
            try? await Task.sleep(for: .seconds(2))
            return try await client.check(wav: wav, at: place)
        }
    }

    private func apply(_ answer: RecitationCheckAnswer) {
        guard answer.status == .checked else { return }
        let changes = Self.marks(for: answer)
        for word in answer.words {
            checked.insert(word.id)
            notes[word.id] = word.notes.isEmpty ? nil : word.notes
        }
        if let end = answer.end?.wordID, lastEnd.map({ end > $0 }) ?? true { lastEnd = end }
        if answer.words.contains(where: { $0.result == .mistake || $0.result == .skipped }) { mistakeNotice += 1 }
        WordHighlights.shared.updateMarks(changes)
    }

    /// Sends the reader to where the recitation was found, when it was found
    /// in one place only (a phrase shared by several surahs moves nobody).
    private func moveIfElsewhere(_ found: RecitationFindAnswer) {
        guard let word = Self.jumpTarget(for: found) else { return }
        lastEnd = word
        LiveRecitation.shared.jump(to: word)
    }

    /// The last word heard, if the place is certain.
    nonisolated static func jumpTarget(for found: RecitationFindAnswer) -> WordID? {
        guard found.status == .found, found.places.count == 1, let place = found.places.first else { return nil }
        return place.end.wordID
    }

    nonisolated static func marks(for answer: RecitationCheckAnswer) -> [WordID: WordMark?] {
        Dictionary(answer.words.map { ($0.id, Optional($0.result.mark)) }, uniquingKeysWith: { _, new in new })
    }
}
