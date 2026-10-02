import CoreText
import Observation
import SwiftUI
import UIKit

// One renderer for all Qur'an text: mushaf lines and verse-by-verse cards.
// It draws the exact verified text word by word, so the same word highlight
// system serves live recitation, the reciter's audio and memorization mode.

/// How a word is marked after live recitation.
enum WordMark: Hashable {
    /// Final transcript matched the text; pronunciation is not assessed.
    case correct
    /// Couldn't tell (neutral dotted underline). Never shown as an error.
    case uncertain
    /// Something clearly different was heard.
    case mistake
    /// Passed over while the words around it were recited.
    case skipped
}

/// Colours and sizes for drawing Qur'an text.
struct QuranTextStyle: Equatable {
    var fontSize: CGFloat = 26
    /// Paragraphs only: distance between lines as a multiple of the size.
    var lineHeight: CGFloat = 1.6
    var ink: UIColor = .white
    /// Ayah-end markers.
    var marker: UIColor = UIColor(red: 0.85, green: 0.68, blue: 0.30, alpha: 1)
    /// Colour letters by tajweed rule (verified dataset, Uthmani/Hafs only).
    var tajweed = false
    /// Dark page: brighter tajweed colours.
    var dark = true
    /// Increase Contrast is on: deeper (or brighter) tajweed colours.
    var highContrast = false
    /// Band behind the ayah being recited or selected; nil for none.
    var band: UIColor?
    /// Soft highlight behind the word being recited.
    var currentWord: UIColor = UIColor(white: 0.55, alpha: 0.30)
    var uncertain: UIColor = UIColor(white: 0.62, alpha: 0.9)
    /// Soft green behind words matched in the final transcript.
    var correct: UIColor = UIColor(red: 0.25, green: 0.85, blue: 0.45, alpha: 0.28)
    /// Bright red: something clearly different was heard.
    var mistake: UIColor = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1)
    /// Memorization mode: blank shapes where the words are.
    var placeholder: UIColor = UIColor(white: 0.55, alpha: 0.20)
    /// How much a justified line's words may be squeezed or stretched
    /// horizontally to fill it (1...1: only the spaces between words grow).
    var stretch: ClosedRange<CGFloat> = 1...1
    /// Thicker strokes for easier reading, as a percentage of the size
    /// (0 = the font as designed). Letter widths don't change, so lines don't move.
    var weight: CGFloat = 0
}

/// A run of consecutive words from one verse.
struct QuranTextPiece: Equatable {
    let words: VerseWords
    /// Word indices within the verse.
    let range: ClosedRange<Int>
    /// Draw the ayah-end marker after the last word.
    let showsVerseEnd: Bool

    static func == (lhs: QuranTextPiece, rhs: QuranTextPiece) -> Bool {
        lhs.words.key == rhs.words.key && lhs.range == rhs.range && lhs.showsVerseEnd == rhs.showsVerseEnd
            && lhs.words.text == rhs.words.text
    }

    /// A whole verse.
    init(verse words: VerseWords) {
        self.words = words
        range = 0...max(words.words.count - 1, 0)
        showsVerseEnd = true
    }

    init(words: VerseWords, range: ClosedRange<Int>, showsVerseEnd: Bool) {
        self.words = words
        self.range = range
        self.showsVerseEnd = showsVerseEnd
    }
}

// MARK: - Highlight state

/// The shared highlight state. Live recitation and the reciter's audio write
/// here; every visible piece of Qur'an text reads from it. Only the lines that
/// show an affected verse are redrawn.
@MainActor
@Observable
final class WordHighlights {
    static let shared = WordHighlights()

    /// Memorization mode: the Arabic is replaced by blank placeholders.
    private(set) var isHidden = false
    /// The verse holding the word being followed. Changes per verse (for
    /// scrolling), not per word.
    private(set) var activeVerse: VerseKey?
    /// The word being followed, for views that turn pages with it. Text views
    /// read `current` instead, which isn't observed, so a new word redraws
    /// only the lines that show it.
    private(set) var activeWord: WordID?
    /// Words marked for review after live recitation.
    private(set) var flaggedCount = 0

    @ObservationIgnored private(set) var current: WordID?
    @ObservationIgnored private(set) var marks: [WordID: WordMark] = [:]
    @ObservationIgnored private(set) var band: VerseKey?
    /// Memorisation: words already recited, shown through the hidden text.
    @ObservationIgnored private(set) var revealed: Set<WordID> = []
    @ObservationIgnored private let views = NSHashTable<QuranTextCanvas>.weakObjects()
    /// The current-word pill sliding from the previous word to the new one.
    @ObservationIgnored private(set) var slide: (from: WordID, to: WordID, start: CFTimeInterval)?
    @ObservationIgnored private var slideLink: CADisplayLink?
    @ObservationIgnored private var slideTarget: DisplayLinkTarget?
    private static let slideDuration: CFTimeInterval = 0.22

    private init() {}

    /// How far the pill has slid to `word` (0...1, eased), or nil if it isn't moving.
    func slideProgress(to word: WordID) -> CGFloat? {
        guard let slide, slide.to == word else { return nil }
        let t = min(1, (CACurrentMediaTime() - slide.start) / Self.slideDuration)
        return CGFloat(1 - pow(1 - t, 3))
    }

    private func startSlide(from previous: WordID?, to word: WordID?) {
        guard let previous, let word, previous.surah == word.surah, !UIAccessibility.isReduceMotionEnabled else {
            slide = nil
            return
        }
        slide = (previous, word, CACurrentMediaTime())
        if slideLink == nil {
            let target = slideTarget ?? DisplayLinkTarget { [weak self] in self?.slideStep() }
            slideTarget = target
            let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick))
            link.add(to: .main, forMode: .common)
            slideLink = link
        }
    }

    private func slideStep() {
        guard let slide else {
            slideLink?.invalidate()
            slideLink = nil
            return
        }
        if CACurrentMediaTime() - slide.start >= Self.slideDuration {
            self.slide = nil
            slideLink?.invalidate()
            slideLink = nil
        }
        redraw([slide.to.verseKey, slide.from.verseKey])
    }

    func register(_ view: QuranTextCanvas) { views.add(view) }
    func unregister(_ view: QuranTextCanvas) { views.remove(view) }

    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        revealed = []
        for view in views.allObjects { view.contentChanged() }
    }

    /// The word being recited (by the user or the reciter), or nil.
    func setCurrent(_ word: WordID?) {
        guard word != current else { return }
        let previous = current
        current = word
        startSlide(from: previous, to: word)
        redraw([previous?.verseKey, word?.verseKey])
        if let word { activeWord = word }
        if let key = word?.verseKey, key != activeVerse { activeVerse = key }
    }

    /// The ayah drawn with a band (recited or selected), or nil.
    func setBand(_ verse: VerseKey?) {
        guard verse != band else { return }
        let previous = band
        band = verse
        redraw([previous, verse])
    }

    /// Memorisation: shows words the reciter has reached. Only lines with
    /// newly revealed words are rebuilt.
    func reveal(_ words: [WordID]) {
        guard isHidden else { return }
        let new = words.filter { !revealed.contains($0) }
        guard !new.isEmpty else { return }
        revealed.formUnion(new)
        let keys = Set(new.map(\.verseKey))
        for view in views.allObjects where !view.verses.isDisjoint(with: keys) { view.contentChanged() }
    }

    /// Adds or clears marks for some words.
    func updateMarks(_ changes: [WordID: WordMark?]) {
        guard !changes.isEmpty else { return }
        var affected: Set<VerseKey> = []
        for (word, mark) in changes where marks[word] != mark {
            marks[word] = mark
            affected.insert(word.verseKey)
        }
        guard !affected.isEmpty else { return }
        flaggedCount = marks.values.filter { $0 != .correct }.count
        redraw(Array(affected))
    }

    /// Clears everything from a recitation session.
    func clearRecitation() {
        let verses = Set(marks.keys.map(\.verseKey)).union([current?.verseKey].compactMap { $0 })
        marks = [:]
        current = nil
        slide = nil
        let wasRevealed = !revealed.isEmpty
        revealed = []
        if wasRevealed, isHidden { for view in views.allObjects { view.contentChanged() } }
        activeVerse = nil
        activeWord = nil
        flaggedCount = 0
        redraw(Array(verses))
    }

    private func redraw(_ verses: [VerseKey?]) {
        let keys = Set(verses.compactMap { $0 })
        guard !keys.isEmpty else { return }
        for view in views.allObjects where !view.verses.isDisjoint(with: keys) {
            view.setNeedsDisplay()
        }
    }
}

/// Calls a closure on every screen refresh (CADisplayLink needs an NSObject).
/// The link runs on the main run loop, so the closure runs on the main actor.
final class DisplayLinkTarget: NSObject {
    private let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    @objc func tick() { MainActor.assumeIsolated { action() } }
}

// MARK: - Canvas

/// Draws Qur'an text with CoreText: justified lines, tajweed colours letter by
/// letter, ayah markers, and per-word highlights.
final class QuranTextCanvas: UIView {
    enum Layout: Equatable {
        /// Wraps like a paragraph: full lines justified, the last line to the right.
        case paragraph
        /// One line stretched to the full width (a mushaf line).
        case justifiedLine
        /// One line, centred (the opening pages, the Bismillah).
        case centredLine
    }

    var onTap: ((WordID?) -> Void)?
    private(set) var verses: Set<VerseKey> = []
    private(set) var pieces: [QuranTextPiece] = []
    private(set) var style = QuranTextStyle()
    private(set) var layoutKind = Layout.paragraph

    private struct Unit {
        let id: WordID
        let text: NSAttributedString
        /// The word's letters within `text` (without marks or the ayah marker).
        let core: NSRange
        let width: CGFloat
    }

    private struct Line {
        let ctLine: CTLine
        let x: CGFloat
        let baseline: CGFloat
        /// Horizontal scale the line is drawn at (see `QuranTextStyle.stretch`).
        let scale: CGFloat
        /// Each word's letters and whole unit, as ranges of the line's string.
        let words: [(id: WordID, core: NSRange, whole: NSRange)]
    }

    private var units: [Unit] = []
    private var spaceWidth: CGFloat = 0
    private var lines: [Line] = []
    private var laidOutSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            WordHighlights.shared.register(self)
        } else {
            WordHighlights.shared.unregister(self)
        }
    }

    func configure(pieces: [QuranTextPiece], style: QuranTextStyle, layout: Layout) {
        guard pieces != self.pieces || style != self.style || layout != layoutKind else { return }
        self.pieces = pieces
        self.style = style
        layoutKind = layout
        verses = Set(pieces.map(\.words.key))
        contentChanged()
    }

    /// Text or colours changed (including memorization mode): rebuild.
    func contentChanged() {
        let hidden = WordHighlights.shared.isHidden
        // Hidden words aren't read out either, so reciting from memory works with VoiceOver.
        accessibilityLabel = hidden ? "Hidden to recite from memory" : pieces.map { piece in
            piece.range.filter { piece.words.words.indices.contains($0) }
                .map { (piece.words.text as NSString).substring(with: piece.words.words[$0].range) }
                .joined(separator: " ")
        }.joined(separator: " ")
        units = Self.makeUnits(pieces, style: style, hidden: hidden ? WordHighlights.shared.revealed : nil)
        spaceWidth = Self.width(of: NSAttributedString(string: " ", attributes: Self.baseAttributes(style)))
        laidOutSize = .zero
        setNeedsDisplay()
    }

    // MARK: Measuring

    /// Height of a paragraph at a width.
    func paragraphHeight(for width: CGFloat) -> CGFloat {
        let count = Self.wrap(units.map(\.width), space: spaceWidth, width: width).count
        let advance = style.fontSize * style.lineHeight
        let room = Self.rooms(style)
        return ceil(room.top + CGFloat(max(count, 1)) * advance + room.bottom)
    }

    /// Width of the pieces on one line at a size, before justification.
    @MainActor
    static func naturalWidth(of pieces: [QuranTextPiece], fontSize: CGFloat) -> CGFloat {
        var style = QuranTextStyle()
        style.fontSize = fontSize
        let units = makeUnits(pieces, style: style, hidden: nil)
        let space = width(of: NSAttributedString(string: " ", attributes: baseAttributes(style)))
        return units.reduce(0) { $0 + $1.width } + space * CGFloat(max(units.count - 1, 0))
    }

    // MARK: Building

    private static func font(_ size: CGFloat) -> CTFont {
        CTFontCreateWithName("AmiriQuran-Regular" as CFString, size, nil)
    }

    private static let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
    private static let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)

    private static let strokeKey = NSAttributedString.Key(kCTStrokeWidthAttributeName as String)
    private static let kernKey = NSAttributedString.Key(kCTKernAttributeName as String)

    private static func baseAttributes(_ style: QuranTextStyle) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [fontKey: font(style.fontSize), colorKey: style.ink.cgColor]
        // Negative stroke width: fill and outline in the text's own colour.
        if style.weight > 0 { attributes[strokeKey] = -style.weight }
        return attributes
    }

    @MainActor
    /// `hidden`: nil when the text is shown; otherwise the words still shown
    /// (already recited) while the rest are hidden.
    private static func makeUnits(_ pieces: [QuranTextPiece], style: QuranTextStyle, hidden: Set<WordID>?) -> [Unit] {
        var result: [Unit] = []
        let base = baseAttributes(style)
        var markerAttributes = base
        markerAttributes[colorKey] = style.marker.cgColor
        let clear = UIColor.clear.cgColor
        for piece in pieces {
            let verse = piece.words
            let text = verse.text as NSString
            let tajweedMarks = style.tajweed
                ? TajweedStore.shared.marks(surah: verse.key.surah, verse: verse.key.verse, displayed: verse.text)
                : []
            for index in piece.range where verse.words.indices.contains(index) {
                let word = verse.words[index]
                let display = word.displayRange
                let unit = NSMutableAttributedString(string: text.substring(with: display), attributes: base)
                if let shown = hidden, !shown.contains(word.id) {
                    unit.addAttribute(colorKey, value: clear, range: NSRange(location: 0, length: unit.length))
                } else {
                    for mark in tajweedMarks {
                        let start = max(mark.range.lowerBound, display.location)
                        let end = min(mark.range.upperBound, NSMaxRange(display))
                        guard end > start else { continue }
                        unit.addAttribute(colorKey, value: tajweedColor(mark.rule, style),
                                          range: NSRange(location: start - display.location, length: end - start))
                    }
                }
                if piece.showsVerseEnd, index == piece.range.upperBound {
                    unit.append(NSAttributedString(string: " \u{06DD}" + arabicDigits(verse.key.verse),
                                                   attributes: markerAttributes))
                }
                result.append(Unit(id: word.id, text: unit,
                                   core: NSRange(location: word.range.location - display.location, length: word.range.length),
                                   width: width(of: unit)))
            }
        }
        return result
    }

    @MainActor private static var tajweedColors: [String: CGColor] = [:]

    @MainActor
    private static func tajweedColor(_ rule: TajweedRule, _ style: QuranTextStyle) -> CGColor {
        let key = "\(rule.rawValue)|\(style.dark)|\(style.highContrast)"
        if let cached = tajweedColors[key] { return cached }
        let color = UIColor(rule.color(dark: style.dark, highContrast: style.highContrast)).cgColor
        tajweedColors[key] = color
        return color
    }

    private static func width(of text: NSAttributedString) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text as CFAttributedString), nil, nil, nil))
    }

    static func arabicDigits(_ value: Int) -> String {
        let digits = Array("٠١٢٣٤٥٦٧٨٩")
        return String(String(value).compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }

    /// Greedy line breaking: which units go on each line.
    private static func wrap(_ widths: [CGFloat], space: CGFloat, width: CGFloat) -> [Range<Int>] {
        guard !widths.isEmpty else { return [] }
        var result: [Range<Int>] = []
        var start = 0
        var used: CGFloat = 0
        for (index, unitWidth) in widths.enumerated() {
            let needed = index == start ? unitWidth : used + space + unitWidth
            if index > start, needed > width {
                result.append(start..<index)
                start = index
                used = unitWidth
            } else {
                used = needed
            }
        }
        result.append(start..<widths.count)
        return result
    }

    /// Room above the first line and below the last for marks that reach
    /// beyond a tight line.
    private static func rooms(_ style: QuranTextStyle) -> (top: CGFloat, bottom: CGFloat) {
        let half = style.fontSize * style.lineHeight / 2
        let size = style.fontSize
        return (max(0, 1.4 * size - (half + inkOffset * size)), max(0, 0.7 * size - (half - inkOffset * size)))
    }

    /// The baseline sits this far (× size) below the middle of a line box, so
    /// the visual weight of Arabic (tall letters and marks above, a few
    /// descenders below) is centred.
    private static let inkOffset: CGFloat = 0.28

    private func ensureLayout() {
        guard laidOutSize != bounds.size else { return }
        laidOutSize = bounds.size
        lines = []
        guard !units.isEmpty, bounds.width > 0 else { return }
        let width = bounds.width

        func makeLine(_ range: Range<Int>, justify: Bool, centre: Bool, baseline: CGFloat) -> Line {
            let string = NSMutableAttributedString()
            var words: [(id: WordID, core: NSRange, whole: NSRange)] = []
            let space = NSAttributedString(string: " ", attributes: Self.baseAttributes(style))
            var spaces: [Int] = []
            for index in range {
                if index > range.lowerBound {
                    spaces.append(string.length)
                    string.append(space)
                }
                let unit = units[index]
                let location = string.length
                string.append(unit.text)
                words.append((unit.id, NSRange(location: location + unit.core.location, length: unit.core.length),
                              NSRange(location: location, length: unit.text.length)))
            }
            let natural = CTLineCreateWithAttributedString(string as CFAttributedString)
            let naturalWidth = CGFloat(CTLineGetTypographicBounds(natural, nil, nil, nil))
            var ctLine = natural
            var lineWidth = naturalWidth
            var scale: CGFloat = 1
            if justify, naturalWidth > 0 {
                // Squeeze or stretch the words a little (within the style's
                // range), then widen the spaces for the rest. Only the spaces:
                // CoreText's own justification stretches letters inside words
                // (kashida), which leaves the harakat out of place.
                scale = min(max(width / naturalWidth, style.stretch.lowerBound), style.stretch.upperBound)
                let target = width / scale
                if !spaces.isEmpty, naturalWidth < target {
                    let extra = (target - naturalWidth) / CGFloat(spaces.count)
                    for location in spaces {
                        string.addAttribute(Self.kernKey, value: extra, range: NSRange(location: location, length: 1))
                    }
                    ctLine = CTLineCreateWithAttributedString(string as CFAttributedString)
                    lineWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
                }
            }
            // Never wider than the view.
            if lineWidth * scale > width, lineWidth > 0 { scale = width / lineWidth }
            let drawnWidth = lineWidth * scale
            let x: CGFloat
            if centre {
                x = (width - drawnWidth) / 2
            } else {
                // Right-to-left: a short line sits against the right edge.
                x = max(0, width - drawnWidth)
            }
            return Line(ctLine: ctLine, x: x, baseline: baseline, scale: scale, words: words)
        }

        switch layoutKind {
        case .paragraph:
            let breaks = Self.wrap(units.map(\.width), space: spaceWidth, width: width)
            let advance = style.fontSize * style.lineHeight
            let top = Self.rooms(style).top
            for (number, range) in breaks.enumerated() {
                let baseline = top + CGFloat(number) * advance + advance / 2 + Self.inkOffset * style.fontSize
                lines.append(makeLine(range, justify: number < breaks.count - 1, centre: false, baseline: baseline))
            }
        case .justifiedLine, .centredLine:
            let baseline = bounds.height / 2 + Self.inkOffset * style.fontSize
            lines.append(makeLine(0..<units.count, justify: layoutKind == .justifiedLine, centre: layoutKind == .centredLine,
                                  baseline: baseline))
        }
    }

    // MARK: Drawing

    private func rect(of range: NSRange, in line: Line) -> CGRect {
        let a = CTLineGetOffsetForStringIndex(line.ctLine, range.location, nil)
        let b = CTLineGetOffsetForStringIndex(line.ctLine, NSMaxRange(range), nil)
        let size = style.fontSize
        let minX = line.x + min(a, b) * line.scale, maxX = line.x + max(a, b) * line.scale
        return CGRect(x: minX - size * 0.08, y: line.baseline - size * 1.2,
                      width: maxX - minX + size * 0.16, height: size * 1.85)
    }

    override func draw(_ rect: CGRect) {
        ensureLayout()
        guard let context = UIGraphicsGetCurrentContext(), !lines.isEmpty else { return }
        let highlights = WordHighlights.shared
        let size = style.fontSize

        for line in lines {
            // The recited or selected ayah: a band behind its words on this line.
            if let bandColor = style.band, let band = highlights.band {
                let inVerse = line.words.filter { $0.id.verseKey == band }
                if let first = inVerse.first, let last = inVerse.last {
                    let union = self.rect(of: first.whole, in: line).union(self.rect(of: last.whole, in: line))
                    bandColor.setFill()
                    UIBezierPath(roundedRect: union.insetBy(dx: -size * 0.1, dy: size * 0.05),
                                 cornerRadius: size * 0.25).fill()
                }
            }
            // Memorization: blank shapes where the words are.
            if highlights.isHidden {
                style.placeholder.setFill()
                for word in line.words where !highlights.revealed.contains(word.id) {
                    let box = self.rect(of: word.core, in: line)
                    UIBezierPath(roundedRect: CGRect(x: box.minX + size * 0.05, y: line.baseline - size * 0.62,
                                                     width: max(box.width - size * 0.1, size * 0.4), height: size * 0.62),
                                 cornerRadius: size * 0.31).fill()
                }
            }
            // Words recited correctly: soft green (only once shown, if hidden).
            for word in line.words where highlights.marks[word.id] == .correct
                && (!highlights.isHidden || highlights.revealed.contains(word.id)) {
                style.correct.setFill()
                UIBezierPath(roundedRect: self.rect(of: word.core, in: line), cornerRadius: size * 0.3).fill()
            }
            // The word being recited: a soft pill, sliding from the previous
            // word when that was on the same line.
            if let current = highlights.current, let word = line.words.first(where: { $0.id == current }) {
                var box = self.rect(of: word.core, in: line)
                if let progress = highlights.slideProgress(to: current), let from = highlights.slide?.from,
                   let previous = line.words.first(where: { $0.id == from }) {
                    let start = self.rect(of: previous.core, in: line)
                    box = CGRect(x: start.minX + (box.minX - start.minX) * progress,
                                 y: start.minY + (box.minY - start.minY) * progress,
                                 width: start.width + (box.width - start.width) * progress,
                                 height: start.height + (box.height - start.height) * progress)
                }
                style.currentWord.setFill()
                UIBezierPath(roundedRect: box, cornerRadius: size * 0.3).fill()
            }
        }

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        for line in lines {
            context.saveGState()
            context.translateBy(x: line.x, y: bounds.height - line.baseline)
            context.scaleBy(x: line.scale, y: 1)
            context.textPosition = .zero
            CTLineDraw(line.ctLine, context)
            context.restoreGState()
        }
        context.restoreGState()

        // Review marks, drawn under the words so the text stays readable.
        // While the text is hidden, only words already recited show theirs.
        for line in lines {
            for word in line.words {
                guard let mark = highlights.marks[word.id], mark != .correct,
                      !highlights.isHidden || highlights.revealed.contains(word.id) else { continue }
                let box = self.rect(of: word.core, in: line)
                let y = line.baseline + size * 0.5
                let path = UIBezierPath()
                path.move(to: CGPoint(x: box.minX + size * 0.1, y: y))
                path.addLine(to: CGPoint(x: box.maxX - size * 0.1, y: y))
                path.lineCapStyle = .round
                switch mark {
                case .correct:
                    continue
                case .uncertain:
                    path.lineWidth = max(1.5, size * 0.06)
                    path.setLineDash([0.1, size * 0.18], count: 2, phase: 0)
                    style.uncertain.setStroke()
                case .mistake:
                    path.lineWidth = max(2, size * 0.08)
                    style.mistake.setStroke()
                case .skipped:
                    path.lineWidth = max(2, size * 0.08)
                    path.setLineDash([size * 0.3, size * 0.15], count: 2, phase: 0)
                    style.mistake.setStroke()
                }
                path.stroke()
            }
        }
    }

    // MARK: Taps

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        ensureLayout()
        let point = gesture.location(in: self)
        let size = style.fontSize
        guard let line = lines.min(by: { abs($0.baseline - size * 0.3 - point.y) < abs($1.baseline - size * 0.3 - point.y) }) else {
            onTap?(nil)
            return
        }
        let index = CTLineGetStringIndexForPosition(line.ctLine, CGPoint(x: (point.x - line.x) / line.scale, y: 0))
        if let word = line.words.first(where: { NSLocationInRange(index, $0.whole) }) {
            onTap?(word.id)
        } else {
            onTap?(line.words.min { abs($0.whole.location - index) < abs($1.whole.location - index) }?.id)
        }
    }
}

// MARK: - SwiftUI

/// Qur'an text in SwiftUI, drawn by `QuranTextCanvas`.
struct QuranTextView: UIViewRepresentable {
    let pieces: [QuranTextPiece]
    let style: QuranTextStyle
    var layout: QuranTextCanvas.Layout = .paragraph
    /// Drawn this many times sharper (the mushaf while zoomed in).
    var sharpness: CGFloat = 1
    var onTap: ((WordID?) -> Void)?

    func makeUIView(context: Context) -> QuranTextCanvas {
        let canvas = QuranTextCanvas()
        canvas.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return canvas
    }

    func updateUIView(_ canvas: QuranTextCanvas, context: Context) {
        canvas.configure(pieces: pieces, style: style, layout: layout)
        canvas.onTap = onTap
        // Without a tap action, touches go to the views around (scrolling, menus).
        canvas.isUserInteractionEnabled = onTap != nil
        let screen = canvas.traitCollection.displayScale > 0 ? canvas.traitCollection.displayScale : 3
        let scale = screen * sharpness
        if canvas.contentScaleFactor != scale {
            canvas.contentScaleFactor = scale
            canvas.setNeedsDisplay()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView canvas: QuranTextCanvas, context: Context) -> CGSize? {
        canvas.configure(pieces: pieces, style: style, layout: layout)
        let width = proposal.width ?? 320
        switch layout {
        case .paragraph:
            return CGSize(width: width, height: canvas.paragraphHeight(for: width))
        case .justifiedLine, .centredLine:
            return CGSize(width: width, height: proposal.height ?? style.fontSize * 1.8)
        }
    }
}
