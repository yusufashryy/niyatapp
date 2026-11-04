import XCTest
@testable import Niyat

/// The recitation check's app side: where it connects, what it sends, and
/// how the server's answer becomes marks on the words.
final class RecitationCheckTests: XCTestCase {

    // MARK: Server address

    func testServerAddressUsesHTTPS() {
        XCTAssertEqual(RecitationCheckSettings.serverURL(from: "203-0-113-7.sslip.io")?.absoluteString,
                       "https://203-0-113-7.sslip.io")
        XCTAssertEqual(RecitationCheckSettings.serverURL(from: "https://check.example.com")?.absoluteString,
                       "https://check.example.com")
    }

    func testPlainHTTPOnlyForThisMac() {
        XCTAssertEqual(RecitationCheckSettings.serverURL(from: "127.0.0.1:8080")?.absoluteString, "http://127.0.0.1:8080")
        XCTAssertEqual(RecitationCheckSettings.serverURL(from: "localhost:8080")?.scheme, "http")
        XCTAssertEqual(RecitationCheckSettings.serverURL(from: "http://example.com")?.scheme, "https")
    }

    func testNoServerWhenNotSet() {
        XCTAssertNil(RecitationCheckSettings.serverURL(from: nil))
        XCTAssertNil(RecitationCheckSettings.serverURL(from: " "))
        XCTAssertNil(RecitationCheckSettings.serverURL(from: "$(RECITATION_SERVER)"))
    }

    func testOnlyTheUthmaniTextsAreChecked() {
        XCTAssertTrue(RecitationCheckSettings.supports(.uthmani))
        XCTAssertTrue(RecitationCheckSettings.supports(.uthmaniMinimal))
        XCTAssertFalse(RecitationCheckSettings.supports(.imlaei))
        XCTAssertFalse(RecitationCheckSettings.supports(.warsh))
    }

    // MARK: What's sent

    func testWAVHeader() {
        let data = WAVFile.data(samples: [0, 1, -1, 32767])
        XCTAssertEqual(data.count, 44 + 8)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<16], as: UTF8.self), "WAVEfmt ")
        XCTAssertEqual(data[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }, 16_000)
        XCTAssertEqual(data[40..<44].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }, 8)
        XCTAssertEqual(data[50..<52].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }, 32767)
    }

    func testRequest() {
        let client = RecitationCheckClient(server: URL(string: "https://check.example.com")!, key: "abc")
        let request = client.request(wav: Data([1, 2]), at: .init(surah: 2, ayah: 255, word: 3))
        XCTAssertEqual(request.url?.absoluteString, "https://check.example.com/v1/check?surah=2&ayah=255&word=3")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "audio/wav")
        XCTAssertEqual(request.httpBody, Data([1, 2]))
    }

    // MARK: The answer

    private let answerJSON = """
    {"version": 1, "status": "checked", "certainty": 0.93,
     "start": {"surah": 1, "ayah": 4, "word": 0}, "end": {"surah": 1, "ayah": 4, "word": 2},
     "words": [
       {"surah": 1, "ayah": 4, "word": 0, "result": "mistake",
        "notes": [{"kind": "letter", "text": "Heard «د» where «ل» is written."}]},
       {"surah": 1, "ayah": 4, "word": 1, "result": "check",
        "notes": [{"kind": "tajweed", "text": "Leen Madd: held for about 1 counts; usually 4.",
                   "rule": {"en": "Leen Madd", "ar": "مد اللين"}}]},
       {"surah": 1, "ayah": 4, "word": 2, "result": "correct", "notes": []}
     ]}
    """

    func testDecodesAnAnswer() throws {
        let answer = try RecitationCheckClient.decode(data: Data(answerJSON.utf8), status: 200)
        XCTAssertEqual(answer.status, .checked)
        XCTAssertEqual(answer.end?.wordID, WordID(surah: 1, verse: 4, index: 2))
        XCTAssertEqual(answer.words[1].notes.first?.rule?.en, "Leen Madd")
    }

    func testResultsBecomeMarks() throws {
        let answer = try RecitationCheckClient.decode(data: Data(answerJSON.utf8), status: 200)
        let marks = RecitationChecker.marks(for: answer)
        XCTAssertEqual(marks[WordID(surah: 1, verse: 4, index: 0)], .some(.mistake))
        XCTAssertEqual(marks[WordID(surah: 1, verse: 4, index: 1)], .some(.check))
        XCTAssertEqual(marks[WordID(surah: 1, verse: 4, index: 2)], .some(.correct))
    }

    func testEveryResultHasAMark() {
        XCTAssertEqual(RecitationCheckAnswer.Result.unsure.mark, .uncertain)
        XCTAssertEqual(RecitationCheckAnswer.Result.skipped.mark, .skipped)
    }

    func testNotFoundHasNoWords() throws {
        let json = #"{"version": 1, "status": "not_found", "certainty": 0.4, "words": []}"#
        let answer = try RecitationCheckClient.decode(data: Data(json.utf8), status: 200)
        XCTAssertEqual(answer.status, .notFound)
        XCTAssertTrue(RecitationChecker.marks(for: answer).isEmpty)
    }

    func testErrors() {
        func error(_ status: Int, _ body: String = "") -> RecitationCheckError? {
            do {
                _ = try RecitationCheckClient.decode(data: Data(body.utf8), status: status)
                return nil
            } catch {
                return error as? RecitationCheckError
            }
        }
        XCTAssertEqual(error(401), .notSetUp)
        XCTAssertEqual(error(429), .busy)
        XCTAssertEqual(error(503), .busy)
        XCTAssertEqual(error(502), .offline)
        XCTAssertEqual(error(400, #"{"detail": "The recording is too short."}"#), .rejected("The recording is too short."))
        XCTAssertEqual(error(200, "{}"), .rejected("The checker sent an answer this version of Niyat can't read."))
    }

    // MARK: The AI notice

    func testNoticeIsQuotedInBothLanguages() {
        XCTAssertTrue(AINotice.english.hasPrefix("This Quranic Teacher is an artificial-intelligence model"))
        XCTAssertTrue(AINotice.arabic.hasPrefix("هذا المعلّم القرآني نموذج ذكاء اصطناعي"))
    }

    // MARK: Finding by reciting

    func testDecodesWhereARecitationIs() throws {
        let json = """
        {"version": 1, "status": "found", "certainty": 0.9, "places": [
          {"start": {"surah": 2, "ayah": 255, "word": 0}, "end": {"surah": 2, "ayah": 255, "word": 12}},
          {"start": {"surah": 2, "ayah": 255, "word": 3}, "end": {"surah": 2, "ayah": 255, "word": 9}},
          {"start": {"surah": 3, "ayah": 2, "word": 0}, "end": {"surah": 3, "ayah": 2, "word": 4}}]}
        """
        let answer = try RecitationCheckClient.decode(RecitationFindAnswer.self, data: Data(json.utf8), status: 200)
        XCTAssertEqual(answer.status, .found)
        // One choice per ayah, best first.
        XCTAssertEqual(RecitationFinder.places(from: answer),
                       [VerseReference(surah: 2, verse: 255), VerseReference(surah: 3, verse: 2)])
    }

    func testNothingFound() throws {
        let json = #"{"version": 1, "status": "not_found", "certainty": 0.3, "places": []}"#
        let answer = try RecitationCheckClient.decode(RecitationFindAnswer.self, data: Data(json.utf8), status: 200)
        XCTAssertEqual(answer.status, .notFound)
        XCTAssertTrue(RecitationFinder.places(from: answer).isEmpty)
    }

    @MainActor
    func testHandoffIsTakenOnceBySurah() {
        RecitationHandoff.pending = VerseReference(surah: 18, verse: 10)
        XCTAssertNil(RecitationHandoff.take(for: 2))
        XCTAssertEqual(RecitationHandoff.take(for: 18), VerseReference(surah: 18, verse: 10))
        XCTAssertNil(RecitationHandoff.take(for: 18))
    }

    func testJumpsOnlyWhenThePlaceIsCertain() throws {
        let one = #"{"version": 1, "status": "found", "certainty": 0.9, "places": [{"start": {"surah": 114, "ayah": 1, "word": 0}, "end": {"surah": 114, "ayah": 2, "word": 1}}]}"#
        let two = #"{"version": 1, "status": "found", "certainty": 0.9, "places": [{"start": {"surah": 2, "ayah": 5, "word": 0}, "end": {"surah": 2, "ayah": 5, "word": 3}}, {"start": {"surah": 31, "ayah": 5, "word": 0}, "end": {"surah": 31, "ayah": 5, "word": 3}}]}"#
        let decode = { (json: String) in try RecitationCheckClient.decode(RecitationFindAnswer.self, data: Data(json.utf8), status: 200) }
        XCTAssertEqual(RecitationChecker.jumpTarget(for: try decode(one)), WordID(surah: 114, verse: 2, index: 1))
        XCTAssertNil(RecitationChecker.jumpTarget(for: try decode(two)))
    }
}
