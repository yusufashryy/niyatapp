import SwiftUI

/// Keeps short labels on one line at every text size, on every device,
/// rather than letting them wrap a letter at a time («NEX/T») or clip.
extension View {
    /// A label in a pill or badge that should never wrap: one line, at its
    /// full size, and the pill grows to fit. Use where the row has room for
    /// the badge to widen (shrink a neighbour with `fitText` if not).
    func badgeText() -> some View {
        lineLimit(1).fixedSize()
    }

    /// A label inside a fixed shape (a circle, a ring, a small square) or a
    /// tight row: one line, shrinking down to `minimumScale` of its size
    /// before it would wrap or clip.
    func fitText(_ minimumScale: CGFloat = 0.6) -> some View {
        lineLimit(1).minimumScaleFactor(minimumScale)
    }
}
