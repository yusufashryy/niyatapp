import SwiftUI

/// The row under the reader for reciting: where things are at and the words
/// to review in one bar, and the Recite button beside it. Only the button
/// shows until there's something to say.
struct RecitationDock: View {
    /// On light mushaf paper.
    var light = false
    let onRecite: () -> Void
    let onReview: () -> Void
    @State private var live = LiveRecitation.shared
    @State private var checker = RecitationChecker.shared
    @State private var highlights = WordHighlights.shared

    private var flagged: Int { highlights.flaggedCount }
    private var isActive: Bool { live.isListening || live.status == .paused || checker.pending > 0 }

    var body: some View {
        HStack(spacing: 12) {
            if isActive || flagged > 0 {
                bar.transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                Spacer(minLength: 0)
            }
            ReciteButton(action: onRecite)
        }
        .padding(.horizontal, 16)
        .animation(.smooth, value: isActive)
        .animation(.smooth, value: flagged > 0)
    }

    private var bar: some View {
        HStack(spacing: 8) {
            if isActive {
                LiveRecitationStatus(light: light, plain: true)
                    .layoutPriority(1)
            }
            Spacer(minLength: 0)
            if flagged > 0 {
                Button(action: onReview) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.badge.checkmark")
                        Text(isActive ? "\(flagged)" : (flagged == 1 ? "1 word to review" : "\(flagged) words to review"))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .opacity(0.7)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Palette.control.gradient, in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(flagged == 1 ? "Review 1 marked word" : "Review \(flagged) marked words")
            }
            if !isActive {
                Button { live.clearReview() } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(ink)
                        .frame(width: 34, height: 34)
                        .contentShape(.circle)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Clear the marks")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .capsule)
        .haptic(.impact(weight: .light), trigger: flagged > 0) { !$0 && $1 }
    }

    private var ink: Color { light ? .black.opacity(0.75) : .white }
}
