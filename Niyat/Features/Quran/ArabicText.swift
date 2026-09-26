import SwiftUI
import UIKit

/// Line spacing for Qur'an text, shared by the verse cards and the mushaf.
/// Measured as line height ÷ text size. Amiri Quran's own line is 2.45×
/// (room for stacked marks); printed mushafs are close to 1.6×.
enum QuranLineSpacing {
    static let key = "quran.lineHeight"
    static let standard = 1.6
    static let range = 1.5...2.5

    static var current: CGFloat {
        let value = UserDefaults.standard.object(forKey: key) as? Double ?? standard
        return CGFloat(min(max(value, range.lowerBound), range.upperBound))
    }

    /// With lines tighter than the font's natural height, the tallest marks on
    /// the first line rise above it; this much room is left for them.
    static func topRoom(for size: CGFloat, lineHeight: CGFloat) -> CGFloat {
        max(0, (1.4 - (lineHeight - 0.634)) * size)
    }

    static func paragraph(_ alignment: NSTextAlignment, size: CGFloat, lineHeight: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.baseWritingDirection = .rightToLeft
        style.lineBreakMode = .byWordWrapping
        style.minimumLineHeight = size * lineHeight
        style.maximumLineHeight = size * lineHeight
        style.lineSpacing = 0
        return style
    }
}

/// A verse in Arabic with tight, adjustable line spacing (SwiftUI's Text can't
/// set lines closer than the font's own height) and optional tajweed colours.
struct ArabicVerseText: UIViewRepresentable {
    let text: String
    let size: CGFloat
    let color: UIColor
    let lineHeight: CGFloat
    /// Surah and verse for tajweed colours, or nil for none.
    var tajweed: (surah: Int, verse: Int)?

    private var attributed: NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont(name: "AmiriQuran-Regular", size: size) ?? .systemFont(ofSize: size),
            .foregroundColor: color,
            .paragraphStyle: QuranLineSpacing.paragraph(.justified, size: size, lineHeight: lineHeight),
        ])
        if let tajweed {
            TajweedStore.shared.colour(result, verseText: text, at: 0, surah: tajweed.surah, verse: tajweed.verse, dark: true)
        }
        return result
    }

    private var topRoom: CGFloat { QuranLineSpacing.topRoom(for: size, lineHeight: lineHeight) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.textContainer.lineFragmentPadding = 0
        view.clipsToBounds = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.textContainerInset = UIEdgeInsets(top: topRoom, left: 0, bottom: 0, right: 0)
        let text = attributed
        if view.attributedText != text { view.attributedText = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let height = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height
        return CGSize(width: width, height: ceil(height) + topRoom + 2)
    }
}
