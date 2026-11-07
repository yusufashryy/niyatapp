import SwiftUI

/// The row under the reader for reciting: where things are at, and the
/// Recite button beside it. Only the button shows until there's something to say.
struct RecitationDock: View {
    /// On light mushaf paper.
    var light = false
    /// False where the Recite button lives in a bar of its own (the mushaf).
    var showsButton = true
    let onRecite: () -> Void
    @State private var live = LiveRecitation.shared

    private var isActive: Bool { live.isListening || live.status == .paused }

    var body: some View {
        HStack(spacing: 12) {
            if isActive {
                bar.transition(.move(edge: .trailing).combined(with: .opacity))
            } else if showsButton {
                Spacer(minLength: 0)
            }
            if showsButton { ReciteButton(action: onRecite) }
        }
        .padding(.horizontal, 16)
        .animation(.smooth, value: isActive)
    }

    private var bar: some View {
        HStack(spacing: 8) {
            LiveRecitationStatus(light: light, plain: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .capsule)
    }
}
