import AppIntents
import SwiftUI
import WidgetKit

/// The style picked under Edit Widget.
enum WidgetStyleOption: String, AppEnum {
    case minimal, theme

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static let caseDisplayRepresentations: [WidgetStyleOption: DisplayRepresentation] = [
        .minimal: DisplayRepresentation(title: "Minimal", subtitle: "Like Apple's widgets; glass in the Clear look"),
        .theme: DisplayRepresentation(title: "Niyat theme", subtitle: "Your theme's colours and artwork"),
    ]

    var style: WidgetLook.Style { WidgetLook.Style(rawValue: rawValue) ?? .default }
}

/// Every Niyat widget has one setting: how it looks.
struct WidgetStyleIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Widget Style"
    static let description = IntentDescription("Choose how the widget looks.")

    @Parameter(title: "Style", default: .minimal)
    var style: WidgetStyleOption

    init() {}
}

/// A widget's entry with the style it was configured with.
struct StyledEntry<Base: TimelineEntry>: TimelineEntry {
    let base: Base
    let style: WidgetLook.Style

    var date: Date { base.date }
    var relevance: TimelineEntryRelevance? { base.relevance }
}

/// Runs one of the widgets' own providers and adds the configured style, so
/// the providers stay as they are.
struct StyledProvider<Base: TimelineProvider>: AppIntentTimelineProvider {
    let base: Base

    func placeholder(in context: Context) -> StyledEntry<Base.Entry> {
        StyledEntry(base: base.placeholder(in: context), style: .default)
    }

    func snapshot(for configuration: WidgetStyleIntent, in context: Context) async -> StyledEntry<Base.Entry> {
        let style = configuration.style.style
        return await withCheckedContinuation { continuation in
            base.getSnapshot(in: context) { continuation.resume(returning: StyledEntry(base: $0, style: style)) }
        }
    }

    func timeline(for configuration: WidgetStyleIntent, in context: Context) async -> Timeline<StyledEntry<Base.Entry>> {
        let style = configuration.style.style
        return await withCheckedContinuation { continuation in
            base.getTimeline(in: context) { timeline in
                let entries = timeline.entries.map { StyledEntry(base: $0, style: style) }
                continuation.resume(returning: Timeline(entries: entries, policy: timeline.policy))
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var widgetLook = WidgetLook(style: .default, isFullColor: true)
}

extension View {
    /// Draws a widget in its configured style.
    func widgetStyle(_ style: WidgetLook.Style) -> some View {
        modifier(WidgetStyleModifier(style: style))
    }

    /// The widget's background: `art` in the Niyat theme, otherwise none
    /// (see `WidgetLook`).
    func widgetBackground<Art: View>(@ViewBuilder _ art: () -> Art) -> some View {
        modifier(WidgetBackgroundModifier(art: art()))
    }
}

private struct WidgetStyleModifier: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let style: WidgetLook.Style

    func body(content: Content) -> some View {
        let look = WidgetLook(style: style, isFullColor: renderingMode == .fullColor)
        let styled = content.environment(\.widgetLook, look)
        if let scheme = look.colorScheme {
            styled.environment(\.colorScheme, scheme)
        } else {
            styled
        }
    }
}

private struct WidgetBackgroundModifier<Art: View>: ViewModifier {
    @Environment(\.widgetLook) private var look
    let art: Art

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            if look.showsArtwork { art } else { Color.clear }
        }
    }
}
