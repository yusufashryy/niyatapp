import Foundation

/// Per-frame log-probabilities from the recitation model: `frames` rows of
/// `vocabulary` values, frame after frame.
struct RecitationLogProbs {
    let frames: Int
    let vocabulary: Int
    let values: [Float]

    subscript(frame: Int, token: Int) -> Float { values[frame * vocabulary + token] }
}

/// The model's vocabulary (word pieces), grouped by the letters each piece
/// spells. Harakat and letter forms are ignored, as in `RecitationMatcher`, so
/// a word can be matched however the model would have spelled it.
struct RecitationVocabulary {
    let pieces: [String]
    let blank: Int
    /// Letters (with a leading word marker for word-initial pieces) to group.
    let groupOf: [[UInt32]: Int]
    let groupMembers: [[Int]]
    /// Pieces that spell no letter (blank, pure harakat, punctuation, <unk>):
    /// they can be emitted anywhere without consuming a letter.
    let fillers: [Int]
    let longestGroup: Int

    /// SentencePiece's word marker.
    static let wordMarker: UInt32 = 0x2581

    /// Reads tokens.txt ("piece id" per line).
    init(tokensFile: String) {
        var pieces: [String] = []
        for line in tokensFile.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: false)
            guard let last = parts.last, let id = Int(last), id >= 0 else { continue }
            let piece = parts.dropLast().joined(separator: " ")
            while pieces.count <= id { pieces.append("") }
            pieces[id] = piece
        }
        self.init(pieces: pieces)
    }

    init(pieces: [String]) {
        self.pieces = pieces
        blank = pieces.firstIndex(of: "<blk>") ?? max(pieces.count - 1, 0)
        var groups: [[UInt32]: [Int]] = [:]
        var fillers = [blank]
        for (id, piece) in pieces.enumerated() where id != blank && !piece.isEmpty {
            let key = Self.letterKey(piece)
            if key.isEmpty { fillers.append(id) } else { groups[key, default: []].append(id) }
        }
        let keys = Array(groups.keys)
        groupOf = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, $0) })
        groupMembers = keys.map { groups[$0] ?? [] }
        self.fillers = fillers
        longestGroup = keys.map(\.count).max() ?? 1
    }

    /// A piece as letters only: the word marker (if it starts a word), then
    /// its letters normalised like the matcher's.
    static func letterKey(_ piece: String) -> [UInt32] {
        let marker = Character(UnicodeScalar(wordMarker)!)
        let startsWord = piece.first == marker
        let body = startsWord ? String(piece.dropFirst()) : piece
        let letters = RecitationMatcher.normalize(body).unicodeScalars.map(\.value)
        return letters.isEmpty && startsWord ? [wordMarker] : (startsWord ? [wordMarker] + letters : letters)
    }

    /// Best log-probability of any piece in each group (frames x groups), and
    /// of any filler (frames).
    func groupLogProbs(_ lp: RecitationLogProbs) -> (groups: [Float], fillers: [Float]) {
        let count = groupMembers.count
        var groups = [Float](repeating: -.infinity, count: lp.frames * count)
        var fill = [Float](repeating: -.infinity, count: lp.frames)
        for t in 0..<lp.frames {
            for (g, members) in groupMembers.enumerated() {
                var best = -Float.infinity
                for id in members { best = max(best, lp[t, id]) }
                groups[t * count + g] = best
            }
            var best = -Float.infinity
            for id in fillers { best = max(best, lp[t, id]) }
            fill[t] = best
        }
        return (groups, fill)
    }

    /// Plain transcription: the most likely piece in each frame, repeats and
    /// blanks removed (for following the reciter between checks).
    func greedyWords(_ lp: RecitationLogProbs) -> [String] {
        var text = ""
        var previous = -1
        for t in 0..<lp.frames {
            var best = 0
            var bestValue = -Float.infinity
            for v in 0..<lp.vocabulary where lp[t, v] > bestValue {
                bestValue = lp[t, v]
                best = v
            }
            if best != previous, best != blank, best < pieces.count { text += pieces[best] }
            previous = best
        }
        let marker = String(Character(UnicodeScalar(Self.wordMarker)!))
        return text.replacingOccurrences(of: marker, with: " ")
            .split(separator: " ").map(String.init)
            .filter { !RecitationMatcher.normalize($0).isEmpty }
    }
}

/// Checks recitation against the words that should have been said.
///
/// Rather than writing down what was heard and comparing spellings (which
/// flags correct words whenever the model's spelling is sloppy), this asks how
/// well the audio fits the expected words, in any spelling of their letters:
/// a CTC forced alignment over every way the vocabulary can spell them. Each
/// word gets the best log-probability each of its pieces reached; a word that
/// wasn't said (skipped, or replaced by another) can't reach a good score.
///
/// In the research run (docs/research/asr-eval-qurankarim.md, "Forced
/// alignment") this flagged 0.2% of correctly recited words and caught 99.3% of
/// skipped and 99.5% of wrong words, at a threshold of -3 on the mean score.
enum RecitationAligner {
    struct Score {
        /// Best log-probability reached by each piece used for the word.
        let pieces: [Float]
        var mean: Float { pieces.reduce(0, +) / Float(max(pieces.count, 1)) }
        var worst: Float { pieces.min() ?? -.infinity }
    }

    private struct Arc {
        let from: Int
        let to: Int
        let group: Int
        let word: Int
    }

    /// Aligns `words` (each with its accepted spellings, as normalised letters)
    /// to the audio. Returns one score per word, or nil when the audio is too
    /// short for the letters (or the words can't be spelled at all).
    static func align(_ lp: RecitationLogProbs, vocabulary: RecitationVocabulary,
                      groupLogProbs: (groups: [Float], fillers: [Float])? = nil,
                      words: [[[UInt32]]]) -> [Score]? {
        guard lp.frames > 0, !words.isEmpty else { return nil }
        let (G, F) = groupLogProbs ?? vocabulary.groupLogProbs(lp)
        let groupCount = vocabulary.groupMembers.count

        // A small graph: nodes between letters, one path per spelling of each
        // word, all spellings of a word sharing its start and end.
        var arcs: [Arc] = []
        var nodeCount = 1
        var wordStart = 0
        for (w, spellings) in words.enumerated() {
            let unique = Array(Set(spellings.filter { !$0.isEmpty }))
            guard !unique.isEmpty else { return nil }
            let end = nodeCount
            nodeCount += 1
            for letters in unique {
                let chars = [RecitationVocabulary.wordMarker] + letters
                var path = [wordStart]
                for _ in 1..<chars.count {
                    path.append(nodeCount)
                    nodeCount += 1
                }
                path.append(end)
                for i in 0..<chars.count {
                    for j in (i + 1)...min(chars.count, i + vocabulary.longestGroup) {
                        if let g = vocabulary.groupOf[Array(chars[i..<j])] {
                            arcs.append(Arc(from: path[i], to: path[j], group: g, word: w))
                        }
                    }
                }
            }
            wordStart = end
        }
        let finalNode = wordStart
        guard !arcs.isEmpty else { return nil }
        var ending = [[Int]](repeating: [], count: nodeCount)
        for (k, arc) in arcs.enumerated() { ending[arc.to].append(k) }

        // Viterbi. States: "between pieces at a node" (blank or filler), or
        // "inside arc k". Back-pointers per frame for the path.
        let T = lp.frames, K = arcs.count
        let neg: Float = -1e30
        var B = [Float](repeating: neg, count: nodeCount)
        var A = [Float](repeating: neg, count: K)
        B[0] = F[0]
        for k in 0..<K where arcs[k].from == 0 { A[k] = G[arcs[k].group] }
        var stayed = [Bool](repeating: false, count: T * K)
        var source = [Int32](repeating: -1, count: T * nodeCount)
        var entry = [Float](repeating: neg, count: nodeCount)
        var entrySource = [Int32](repeating: -1, count: nodeCount)

        func computeEntry() {
            for node in 0..<nodeCount {
                var best = B[node]
                var from: Int32 = -1
                for k in ending[node] where A[k] > best {
                    best = A[k]
                    from = Int32(k)
                }
                entry[node] = best
                entrySource[node] = from
            }
        }

        for t in 1..<max(T, 1) {
            computeEntry()
            var newA = [Float](repeating: neg, count: K)
            for k in 0..<K {
                let fromEntry = entry[arcs[k].from]
                let stay = A[k] >= fromEntry
                newA[k] = (stay ? A[k] : fromEntry) + G[t * groupCount + arcs[k].group]
                stayed[t * K + k] = stay
            }
            for node in 0..<nodeCount {
                B[node] = entry[node] + F[t]
                source[t * nodeCount + node] = entrySource[node]
            }
            A = newA
        }
        computeEntry()
        guard entry[finalNode] > neg / 2 else { return nil }

        // Back through the path: the best value each arc reached.
        var best = [Int: Float]()
        var arc: Int? = entrySource[finalNode] >= 0 ? Int(entrySource[finalNode]) : nil
        var node = finalNode
        var t = T - 1
        while t >= 0 {
            if let k = arc {
                best[k] = max(best[k] ?? neg, G[t * groupCount + arcs[k].group])
                if t == 0 { break }
                if stayed[t * K + k] {
                    t -= 1
                    continue
                }
                node = arcs[k].from
            } else if t == 0 {
                break
            }
            let from = source[t * nodeCount + node]
            arc = from >= 0 ? Int(from) : nil
            t -= 1
        }
        var pieces = [[Float]](repeating: [], count: words.count)
        for (k, value) in best { pieces[arcs[k].word].append(value) }
        return pieces.map { Score(pieces: $0.isEmpty ? [neg] : $0) }
    }
}
