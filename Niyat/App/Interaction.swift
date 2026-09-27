import SwiftUI

// Shared feel for the whole app: haptics, press effects and entrance animations.

enum Haptics {
    static let settingKey = "hapticsEnabled"

    /// Users can turn haptics off in Settings.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }
}

extension View {
    /// Plays a haptic when `trigger` changes (if haptics are on).
    func haptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        sensoryFeedback(feedback, trigger: trigger) { _, _ in Haptics.isEnabled }
    }

    /// Plays a haptic when `trigger` changes and `condition(old, new)` is true.
    func haptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T,
                              when condition: @escaping (T, T) -> Bool) -> some View {
        sensoryFeedback(feedback, trigger: trigger) { old, new in Haptics.isEnabled && condition(old, new) }
    }

    /// Fades and slides the view in the first time it appears. Pass an index to
    /// stagger a list of items.
    func appearAnimation(_ index: Int = 0, enabled: Bool = true) -> some View {
        modifier(AppearAnimation(delay: Double(min(index, 12)) * 0.05, enabled: enabled))
    }

    /// Keeps a screen's content a comfortable width, centred (on iPad and in
    /// landscape; on iPhone in portrait it changes nothing).
    func readableWidth(_ width: CGFloat = 700) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }

    /// Rows coming up from the bottom fade straight in, once, rather than
    /// following the finger; rows leaving at the top don't fade.
    func scrollFade() -> some View {
        scrollTransition(.animated(.smooth(duration: 0.35)), axis: .vertical) { content, phase in
            content.opacity(phase == .bottomTrailing ? 0 : 1)
        }
    }
}

private struct AppearAnimation: ViewModifier {
    let delay: Double
    let enabled: Bool
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shown = visible || !enabled
        return content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .blur(radius: shown || reduceMotion ? 0 : 6)
            .onAppear {
                guard !visible, enabled else { return }
                withAnimation(.smooth(duration: 0.55).delay(delay)) { visible = true }
            }
    }
}

/// Buttons and cards shrink slightly with a light tap when pressed.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.68), value: configuration.isPressed)
            .haptic(.impact(weight: .light, intensity: 0.7), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// Standard iOS switch, tinted so "on" is always easy to see against the knob.
struct NiyatToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .tint(Palette.control)
    }
}
