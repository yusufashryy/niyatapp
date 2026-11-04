import Foundation

/// The server's answer for one recording (see server/README.md).
struct RecitationCheckAnswer: Decodable, Equatable {
    struct Place: Codable, Equatable {
        let surah: Int
        let ayah: Int
        let word: Int

        var wordID: WordID { WordID(surah: surah, verse: ayah, index: word) }
    }

    enum Result: String, Decodable {
        case correct, unsure, check, mistake, skipped

        var mark: WordMark {
            switch self {
            case .correct: .correct
            case .unsure: .uncertain
            case .check: .check
            case .mistake: .mistake
            case .skipped: .skipped
            }
        }
    }

    struct Note: Decodable, Hashable {
        struct Rule: Decodable, Hashable {
            let en: String
            let ar: String
        }

        let kind: String
        let text: String
        let rule: Rule?
    }

    struct Word: Decodable, Equatable {
        let surah: Int
        let ayah: Int
        let word: Int
        let result: Result
        let notes: [Note]

        var id: WordID { WordID(surah: surah, verse: ayah, index: word) }
    }

    enum Status: String, Decodable {
        case checked
        case notFound = "not_found"
        case silence
    }

    let version: Int
    let status: Status
    let certainty: Double
    let start: Place?
    let end: Place?
    let words: [Word]
}

/// The server's answer to "where is this?" (POST /v1/find).
struct RecitationFindAnswer: Decodable, Equatable {
    struct Span: Decodable, Equatable {
        let start: RecitationCheckAnswer.Place
        let end: RecitationCheckAnswer.Place
    }

    enum Status: String, Decodable {
        case found
        case notFound = "not_found"
        case silence
    }

    let version: Int
    let status: Status
    let places: [Span]
}

enum RecitationCheckError: Error, Equatable {
    /// The key or address in this build is wrong: stop trying this session.
    case notSetUp
    /// Too many at once, or the server is busy: try again shortly.
    case busy
    /// No connection, or the server didn't answer.
    case offline
    case rejected(String)
}

/// Sends a recording to the server and reads the answer.
struct RecitationCheckClient {
    let server: URL
    let key: String
    var session: URLSession = .shared

    func request(wav: Data, at place: RecitationCheckAnswer.Place) -> URLRequest {
        var components = URLComponents(url: server.appending(path: "v1/check"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "surah", value: String(place.surah)),
            URLQueryItem(name: "ayah", value: String(place.ayah)),
            URLQueryItem(name: "word", value: String(place.word)),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 40)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wav
        return request
    }

    func check(wav: Data, at place: RecitationCheckAnswer.Place) async throws -> RecitationCheckAnswer {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request(wav: wav, at: place))
        } catch {
            throw RecitationCheckError.offline
        }
        return try Self.decode(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    func find(wav: Data) async throws -> RecitationFindAnswer {
        var request = URLRequest(url: server.appending(path: "v1/find"), timeoutInterval: 40)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wav
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RecitationCheckError.offline
        }
        return try Self.decode(RecitationFindAnswer.self, data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func decode(data: Data, status: Int) throws -> RecitationCheckAnswer {
        try decode(RecitationCheckAnswer.self, data: data, status: status)
    }

    static func decode<Answer: Decodable>(_ type: Answer.Type, data: Data, status: Int) throws -> Answer {
        switch status {
        case 200:
            guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else {
                throw RecitationCheckError.rejected("The checker sent an answer this version of Niyat can't read.")
            }
            return answer
        case 401, 403, 404: throw RecitationCheckError.notSetUp
        case 429, 503: throw RecitationCheckError.busy
        case 500...599: throw RecitationCheckError.offline
        default:
            let detail = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"]
            throw RecitationCheckError.rejected(detail ?? "The checker couldn't read this recording.")
        }
    }
}
