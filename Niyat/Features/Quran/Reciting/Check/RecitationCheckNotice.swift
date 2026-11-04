import SwiftUI

/// The AI notice Quran Muaalem's licence (QML 1.0, condition 1) requires
/// before first use and always within reach. Quoted exactly; the Arabic is
/// the reference.
enum AINotice {
    static let arabic = "هذا المعلّم القرآني نموذج ذكاء اصطناعي قد يخطئ؛ فهو للإعانة فقط ولا يُعتمد عليه، وليس بديلاً عن معلّمٍ مُتقِنٍ مُجاز؛ لأنّ القرآن لا يُؤخذ إلا بالمشافهة."
    static let english = "This Quranic Teacher is an artificial-intelligence model that may make mistakes. It is intended for assistance only and must not be relied upon. It is not a replacement for a proficient, authorized teacher, because the Quran is only received through oral transmission (mushafahah)."
    static let precedence = "The Arabic text is the reference if the two differ."
}

/// What the recitation check does, the AI notice, and where the audio goes.
/// Shown before first use and from Qur'an settings.
struct RecitationCheckExplainer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            notice
            point("waveform.badge.magnifyingglass", "Checks what you recite",
                  "Each time you pause, the part you just recited is checked by Quran Muaalem, an open-source AI model trained on expert recitations. It listens for letters, vowels and some tajweed, and marks the words.")
            marks
            point("lock.shield", "Your recitation",
                  "Each part is sent over an encrypted connection to Niyat's server, checked straight away and then deleted. It's never saved or linked to you, and nobody listens to it. The check needs an internet connection; without one, Niyat follows you with speech recognition as before.")
            point("book", "The text it knows",
                  "Hafs ʿan ʿAsim, in the Uthmani text. It accepts stopping on a word, going back to repeat, and the madd lengths the reading allows.")
        }
    }

    private var notice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI notice", systemImage: "exclamationmark.bubble")
                .font(.headline)
                .foregroundStyle(Palette.highlight)
            Text(AINotice.arabic)
                .font(.system(.body, design: .default))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)
                .accessibilityLabel(Text(AINotice.arabic))
            Text(AINotice.english)
                .font(.subheadline)
            Text(AINotice.precedence)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
        .accessibilityElement(children: .combine)
    }

    private var marks: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "text.badge.checkmark")
                .font(.title3)
                .foregroundStyle(Palette.highlight)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 8) {
                Text("How words are marked").font(.headline)
                legend(.mistake, "A letter sounded different or was missing")
                legend(.skipped, "The word wasn't heard")
                legend(.check, "A vowel or tajweed point to check")
                legend(.uncertain, "The model wasn't sure what it heard")
            }
        }
        .foregroundStyle(.white)
    }

    private func legend(_ mark: WordMark, _ text: String) -> some View {
        HStack(spacing: 10) {
            MarkSwatch(mark: mark)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func point(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Palette.highlight)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
}

/// The page in the first-use sheet: the explainer, then turn it on or not.
struct RecitationCheckChoice: View {
    let onChoice: (Bool) -> Void

    var body: some View {
        ScrollView {
            RecitationCheckExplainer()
                .padding(20)
                .readableWidth()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button { choose(true) } label: {
                    Text("Turn on the check").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.control)
                .controlSize(.large)
                Button("Not now, just follow me") { choose(false) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(20)
            .background { BottomFade() }
        }
        .navigationTitle("Recitation check")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choose(_ on: Bool) {
        RecitationCheckSettings.noticeSeen = true
        RecitationCheckSettings.isEnabled = on
        onChoice(on)
    }
}

/// From Qur'an settings: the explainer and the switch, always within reach.
struct RecitationCheckAboutView: View {
    @AppStorage(RecitationCheckSettings.enabledKey) private var enabled = false

    var body: some View {
        Form {
            Section {
                Toggle("Check my recitation", isOn: Binding(get: { enabled }, set: { on in
                    RecitationCheckSettings.noticeSeen = true
                    enabled = on
                }))
            } footer: {
                Text("Hafs, Uthmani text only. Uses the internet while you recite.")
            }
            Section {
                RecitationCheckExplainer()
                    .padding(.vertical, 8)
            }
            Section {
                Text("Quran Muaalem (github.com/obadx/quran-muaalem) is open source under the Quran Muaalem License 1.0: Apache 2.0 with conditions, including this notice, no advertising, and following Islamic law in its use.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Credit")
            }
        }
        .scrollContentBackground(.hidden)
        .niyatBackground()
        .navigationTitle("Recitation check")
        .navigationBarTitleDisplayMode(.inline)
    }
}
