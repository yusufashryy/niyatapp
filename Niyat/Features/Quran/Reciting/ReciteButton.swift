import SwiftUI

/// The one Recite button, on its own beside the reader's controls: big
/// enough to find without looking, with a ring that moves with your voice
/// and a clear look for each state (starting, listening, following, lost,
/// paused, checking).
struct ReciteButton: View {
    let action: () -> Void
    @State private var live = LiveRecitation.shared
    @State private var checker = RecitationChecker.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size: CGFloat = 64
    /// Room around the button for the voice ring, so it never spills onto
    /// what's next to it and the button stays centred in its space.
    private let ringRoom: CGFloat = 8

    var body: some View {
        Button(action: action) {
            ZStack {
                voiceRing
                Circle()
                    .fill(Palette.control.gradient)
                    .overlay { Circle().strokeBorder(Palette.highlight.opacity(0.5), lineWidth: 1) }
                    .shadow(color: Palette.control.opacity(live.isListening ? 0.5 : 0.25), radius: 12, y: 3)
                icon
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.black)
            }
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) { checkingBadge }
            .frame(width: size + 2 * ringRoom, height: size + 2 * ringRoom)
            .contentShape(.circle)
        }
        .buttonStyle(.pressable)
        .haptic(.impact(weight: .light), trigger: live.isListening)
        .accessibilityLabel(live.isListening ? "Stop reciting" : "Recite")
        .accessibilityValue(stateDescription)
        .accessibilityHint(live.isListening ? "Stops listening. Marked words stay for you to review."
                                            : "Niyat follows you word by word as you recite.")
        .accessibilityIdentifier("reciteButton")
        .animation(reduceMotion ? nil : .smooth, value: live.status)
    }

    @ViewBuilder
    private var icon: some View {
        switch live.status {
        case .starting:
            ProgressView().tint(.black)
        case .searching, .following, .lost:
            Image(systemName: "stop.fill")
                .contentTransition(.symbolEffect(.replace))
        case .idle, .paused, .unavailable:
            Image(systemName: "mic.fill")
                .contentTransition(.symbolEffect(.replace))
        }
    }

    /// Grows with the voice (still with Reduce Motion: just shown, not moving).
    private var voiceRing: some View {
        let listening = live.isListening
        let level = reduceMotion ? 0.3 : CGFloat(live.level)
        return Circle()
            .stroke(ringColor, lineWidth: 4)
            // At its loudest the ring fills the room around the button, no more.
            .scaleEffect(listening ? 1.06 + level * ((size + 2 * ringRoom) / size - 1.06) : 1)
            .opacity(listening ? 0.85 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: live.level)
            .accessibilityHidden(true)
    }

    private var ringColor: Color {
        switch live.status {
        case .following: Palette.highlight
        case .lost: .orange
        default: .white.opacity(0.7)
        }
    }

    @ViewBuilder
    private var checkingBadge: some View {
        if checker.pending > 0 {
            ProgressView()
                .controlSize(.mini)
                .tint(.white)
                .padding(5)
                .background(.black.opacity(0.6), in: .circle)
                .offset(x: 4, y: -4)
                .accessibilityHidden(true)
        }
    }

    private var stateDescription: String {
        var parts: [String] = []
        switch live.status {
        case .starting: parts.append("Starting")
        case .searching: parts.append("Listening for where you are")
        case .following: parts.append("Following you")
        case .lost: parts.append("Can't find your place")
        case .paused: parts.append("Paused after a long silence")
        case .idle, .unavailable: break
        }
        if checker.pending > 0 { parts.append("checking your recitation") }
        return parts.joined(separator: ", ")
    }
}
