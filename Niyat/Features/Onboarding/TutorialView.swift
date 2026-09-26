import SwiftUI

/// A short swipeable walkthrough of how to use Niyat. Shown once after
/// onboarding and any time from More › How to use Niyat.
struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TutorialView.seenKey) private var seen = false
    @State private var page = 0

    static let seenKey = "tutorial.seen"

    private var pages: [TutorialPage] {
        [
            TutorialPage(icon: "hand.wave.fill", title: "Welcome to Niyat",
                         subtitle: "A one-minute tour. Swipe to go through it, or skip and come back any time from More › How to use Niyat.",
                         points: []),
            TutorialPage(icon: "clock.fill", title: "Prayer times",
                         subtitle: "Times are calculated on your phone for where you are. If they don't match your local mosque, change the method here or later in Settings.",
                         points: [],
                         action: .prayerTimes),
            TutorialPage(icon: "sun.horizon.fill", title: "Today",
                         subtitle: "Your day at a glance.",
                         points: [
                             TutorialPoint("circle.dotted", "The dial shows today's five prayers. The glowing marker is now, and the centre counts down to the next prayer."),
                             TutorialPoint("checkmark.circle.fill", "After a prayer's time begins, tap the circle next to it to check in: on time, late, or missed."),
                             TutorialPoint("questionmark.bubble.fill", "If you missed one, pick a reason. It stays private and helps you spot patterns in Stats."),
                             TutorialPoint("bell.fill", "The bell on each row turns that prayer's alerts on or off."),
                         ]),
            TutorialPage(icon: "bell.badge.fill", title: "Prayer notifications",
                         subtitle: "Niyat can remind you before, at, and after each prayer.",
                         points: [
                             TutorialPoint("hand.point.up.left.fill", "Press and hold a prayer alert, then tap Log Prayer. It's logged without opening the app, and never counted twice."),
                             TutorialPoint("arrow.clockwise", "iOS only lets apps queue so many alerts, so open Niyat every couple of days to keep them coming."),
                             TutorialPoint("gearshape.fill", "Set it up below. You can change it any time in More › Settings."),
                         ],
                         action: .notifications),
            TutorialPage(icon: "book.closed.fill", title: "Qur'an",
                         subtitle: "Read a little every day.",
                         points: [
                             TutorialPoint("target", "Set a daily goal in ayat. A verse counts once it has been on screen for a few seconds. The ring at the top shows today's progress."),
                             TutorialPoint("speaker.wave.2.fill", "Tap the speaker on any verse to hear it, or play to recite on. The text follows the reciter word by word."),
                             TutorialPoint("mic.fill", "Tap the mic and recite: Niyat follows you word by word and marks words to double-check. The eye next to it hides the text so you can recite from memory."),
                             TutorialPoint("book.pages.fill", "The book icon opens the mushaf: the 604 pages of the Madinah mushaf, line for line. Swipe right-to-left like a printed copy."),
                             TutorialPoint("bell.badge.fill", "The bell sets Qur'an reminders: morning, afternoon, streak, verse of the day and Surah Al-Kahf on Fridays."),
                         ],
                         action: .quran),
            TutorialPage(icon: "location.north.circle.fill", title: "Qibla",
                         subtitle: "Find the direction of the Ka'bah.",
                         points: [
                             TutorialPoint("iphone", "Hold your phone flat, screen up, away from magnets and metal."),
                             TutorialPoint("arrow.triangle.turn.up.right.circle.fill", "Turn until the arrow lines up at the top. You'll feel a tap when you're facing the Qibla."),
                             TutorialPoint("infinity", "If accuracy is poor, move your phone in a figure-8 a few times."),
                         ]),
            TutorialPage(icon: "chart.bar.xaxis", title: "Stats",
                         subtitle: "See how consistent you're being.",
                         points: [
                             TutorialPoint("calendar", "The calendar colours each day by how many prayers you logged."),
                             TutorialPoint("exclamationmark.bubble.fill", "See which prayers you miss most, and why."),
                             TutorialPoint("flame.fill", "Switch to Qur'an for your reading streak, ayat read and an estimate of the reward."),
                         ]),
            TutorialPage(icon: "square.grid.2x2.fill", title: "Widgets",
                         subtitle: "Keep it on your Home and Lock Screen.",
                         points: [
                             TutorialPoint("hand.tap.fill", "Touch and hold an empty spot on your Home Screen, tap Edit › Add Widget, and search for Niyat."),
                             TutorialPoint("checkmark.circle.fill", "The Prayer Log widget lets you check in right from the Home Screen."),
                             TutorialPoint("lock.fill", "On the Lock Screen, touch and hold, tap Customize, then add a Niyat widget under the clock."),
                         ]),
            TutorialPage(icon: "paintpalette.fill", title: "Make it yours",
                         subtitle: "Everything else lives in More.",
                         points: [
                             TutorialPoint("swatchpalette.fill", "Themes: Onyx, Midnight, Emerald and more, or build your own colours."),
                             TutorialPoint("circle.hexagongrid.fill", "Tasbih: a counter for your dhikr."),
                             TutorialPoint("gearshape.fill", "Settings: calculation method, Asr time, haptics, and erase all data."),
                             TutorialPoint("heart.fill", "Support Niyat and Send feedback: optional tips, and a direct line for ideas or anything that looks wrong."),
                         ],
                         action: .style),
        ]
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if page < pages.count - 1 {
                        Button("Skip") { finish() }
                            .buttonStyle(.glass)
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: 44)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, content in
                        ScrollView {
                            pageView(content)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                        }
                        .scrollIndicators(.hidden)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .haptic(.selection, trigger: page)

                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Palette.accent : .white.opacity(0.2))
                            .frame(width: index == page ? 22 : 8, height: 8)
                    }
                }
                .animation(.smooth, value: page)
                .padding(.vertical, 12)

                Button {
                    if page < pages.count - 1 {
                        withAnimation(.smooth) { page += 1 }
                    } else {
                        finish()
                    }
                } label: {
                    Text(page < pages.count - 1 ? "Next" : "Start using Niyat")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.accent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .foregroundStyle(.white)
    }

    private func pageView(_ content: TutorialPage) -> some View {
        VStack(spacing: 18) {
            ZStack {
                Rosette(color: Palette.highlight.opacity(0.3), lineWidth: 1)
                    .frame(width: 150, height: 150)
                Image(systemName: content.icon)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Palette.highlight)
                    .frame(width: 86, height: 86)
                    .glassEffect(.regular.tint(Palette.glow.opacity(0.5)), in: .circle)
            }
            .padding(.top, 8)

            Text(content.title)
                .font(.display(30, weight: .heavy))
                .multilineTextAlignment(.center)
            Text(content.subtitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))

            if !content.points.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(content.points) { point in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: point.icon)
                                .font(.headline)
                                .foregroundStyle(Palette.accent)
                                .frame(width: 26)
                            Text(point.text)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .surface(cornerRadius: 22)
            }

            switch content.action {
            case .prayerTimes: TutorialPrayerSetup()
            case .notifications: TutorialNotificationSetup()
            case .quran: TutorialQuranSetup()
            case .style: TutorialStyleSetup()
            case nil: EmptyView()
            }
        }
    }

    private func finish() {
        seen = true
        dismiss()
    }
}

private struct TutorialPage {
    enum Action { case prayerTimes, notifications, quran, style }

    let icon: String
    let title: String
    let subtitle: String
    let points: [TutorialPoint]
    var action: Action?
}

private struct TutorialPoint: Identifiable {
    let icon: String
    let text: String
    var id: String { text }

    init(_ icon: String, _ text: String) {
        self.icon = icon
        self.text = text
    }
}
