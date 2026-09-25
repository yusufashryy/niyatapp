import SwiftUI
import WidgetKit

/// Settings › Appearance › Theme: preset colour schemes plus your own colours.
struct ThemePickerView: View {
    private var themes: ThemeManager { ThemeManager.shared }
    @State private var customAccent: Color = ThemeManager.shared.customAccent.color
    @State private var customHighlight: Color = ThemeManager.shared.customHighlight.color

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ThemePreview()
                    .appearAnimation(0)

                Text("Themes").sectionLabelStyle().padding(.top, 6)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(AppTheme.presets.enumerated()), id: \.element.id) { index, theme in
                        ThemeCard(theme: theme, isSelected: themes.selectedID == theme.id) {
                            apply { themes.select(theme.id) }
                        }
                        .appearAnimation(1 + index)
                    }
                }

                Text("Your own colours").sectionLabelStyle().padding(.top, 6)
                VStack(spacing: 0) {
                    ColorPicker(selection: $customAccent, supportsOpacity: false) {
                        Label("Accent", systemImage: "paintbrush.pointed.fill")
                    }
                    .padding(16)
                    Divider().overlay(Palette.hairline)
                    ColorPicker(selection: $customHighlight, supportsOpacity: false) {
                        Label("Highlight", systemImage: "sparkles")
                    }
                    .padding(16)
                    Divider().overlay(Palette.hairline)
                    Button {
                        applyCustom()
                    } label: {
                        HStack {
                            Text(themes.selectedID == "custom" ? "Using your colours" : "Use my colours")
                                .font(.headline)
                            Spacer()
                            if themes.selectedID == "custom" {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Palette.accent)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(16)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.pressable)
                }
                .surface(cornerRadius: 22)
                .appearAnimation(8)

                Text("Your theme also colours the widgets.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .niyatBackground()
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
        .haptic(.selection, trigger: themes.selectedID)
        .onChange(of: customAccent) { if themes.selectedID == "custom" { applyCustom() } }
        .onChange(of: customHighlight) { if themes.selectedID == "custom" { applyCustom() } }
    }

    private func applyCustom() {
        apply { themes.setCustom(accent: ThemeColor(customAccent), highlight: ThemeColor(customHighlight)) }
    }

    private func apply(_ change: () -> Void) {
        withAnimation(.smooth(duration: 0.6)) { change() }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// A mini version of the Today screen in the current theme.
private struct ThemePreview: View {
    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Next prayer").sectionLabelStyle().foregroundStyle(Palette.accent)
                    Spacer()
                    Text("العصر").font(.calligraphy(size: 26)).foregroundStyle(Palette.highlight)
                }
                Text("4:05 PM").font(.display(40, weight: .heavy))
                HStack(spacing: 8) {
                    Capsule().fill(Palette.accent).frame(width: 90, height: 30)
                        .overlay(Text("in 1:24").font(.caption.weight(.bold)).foregroundStyle(.black))
                    Capsule().fill(.white.opacity(0.1)).frame(width: 60, height: 30)
                    Spacer()
                    EightPointStar().fill(Palette.highlight).frame(width: 26, height: 26)
                }
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .frame(height: 190)
        .clipShape(.rect(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(Palette.hairline) }
    }
}

private struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    theme.base.color
                    RadialGradient(colors: [theme.glow.color, .clear], center: .topLeading, startRadius: 0, endRadius: 140)
                    RadialGradient(colors: [theme.glow2.color, .clear], center: .bottomTrailing, startRadius: 0, endRadius: 120)
                    IslamicPattern(tile: 30, lineWidth: 0.6, color: theme.accent.color.opacity(0.18))
                    HStack(spacing: -6) {
                        Circle().fill(theme.accent.color).frame(width: 26, height: 26)
                        Circle().fill(theme.highlight.color).frame(width: 26, height: 26)
                            .overlay(Circle().stroke(theme.base.color, lineWidth: 2))
                    }
                }
                .frame(height: 84)
                .clipShape(.rect(cornerRadius: 16))

                HStack {
                    Text(theme.name).font(.headline)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? theme.accent.color : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundStyle(.white)
            }
            .padding(10)
            .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(isSelected ? theme.accent.color : Palette.hairline, lineWidth: isSelected ? 2 : 1)
            }
            .scaleEffect(isSelected ? 1 : 0.98)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(theme.name) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
