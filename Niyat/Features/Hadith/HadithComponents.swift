import SwiftUI

// The building blocks of the Hadith screens.

extension HadithScenario {
    /// A colour of its own, so the situations are easy to tell apart.
    var tint: Color {
        switch title {
        case "Anger": .red
        case "Parents", "Marriage", "Kindness": .pink
        case "Patience", "Knowledge": .indigo
        case "Grief", "Illness": .blue
        case "Debt", "Charity": .green
        case "Neighbours", "Honesty": .teal
        case "Prayer", "Fasting": .orange
        case "Repentance": .purple
        default: .gray
        }
    }
}

extension HadithTopic {
    /// An icon for the top-level topics of the encyclopedia.
    var icon: String {
        switch id {
        case 1: "book.closed.fill"
        case 2: "text.quote"
        case 3: "sparkles"
        case 4: "building.columns.fill"
        case 5: "heart.text.square.fill"
        case 6: "megaphone.fill"
        case 7: "clock.arrow.circlepath"
        default: "folder.fill"
        }
    }
}

/// "Sahih" or "Hasan", always next to a hadith.
struct GradeBadge: View {
    let level: HadithLevel

    var body: some View {
        Label(level.title, systemImage: "checkmark.seal.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(level == .sahih ? Palette.highlight : Palette.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((level == .sahih ? Palette.highlight : Palette.accent).opacity(0.14), in: .capsule)
            .accessibilityLabel("Graded \(level.title)")
    }
}

/// Today's hadith, centred: a label between ornaments, the opening Arabic,
/// the title as a quote, then grade and source.
struct HadithOfTheDayCard: View {
    let hadith: Hadith
    var onShare: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                EightPointStar().fill(Palette.highlight.opacity(0.7)).frame(width: 7, height: 7)
                Text("Hadith of the day")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Palette.highlight)
                EightPointStar().fill(Palette.highlight.opacity(0.7)).frame(width: 7, height: 7)
            }
            if !hadith.arabic.isEmpty {
                Text(Self.opening(of: hadith.arabic))
                    .font(.system(size: 22))
                    .lineSpacing(6)
                    .foregroundStyle(Palette.highlight)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .rightToLeft)
            }
            OrnamentDivider().frame(width: 110)
            Text("“\(hadith.title)”")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                GradeBadge(level: hadith.level)
                Text(hadith.source).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .overlay(alignment: .topTrailing) {
            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.08), in: .circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(12)
            .accessibilityLabel("Share the hadith")
        }
        .background {
            EightPointStar()
                .stroke(Palette.highlight.opacity(0.07), lineWidth: 1.5)
                .frame(width: 260, height: 260)
        }
        .clipShape(.rect(cornerRadius: 28))
        .glassPanel(cornerRadius: 28, tint: Palette.glow.opacity(0.35), interactive: true)
    }

    /// The Prophet's words, without the chain before them when it can be found.
    static func opening(of arabic: String) -> String {
        if let start = arabic.firstIndex(of: "«") { return String(arabic[start...]) }
        return arabic
    }
}

/// How many hadiths, which grades, what each comes with.
struct TrustStrip: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            pill("\(count.formatted())", "hadiths", "books.vertical.fill")
            pill("Sahih", "& Hasan", "checkmark.seal.fill")
            pill("Explained", "with lessons", "lightbulb.fill")
        }
    }

    private func pill(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.footnote).foregroundStyle(Palette.highlight)
            Text(value).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .surface(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }
}

/// Everyday situations, all at once: coloured chips that wrap onto new lines.
struct ScenarioCloud: View {
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(HadithScenario.all) { scenario in
                NavigationLink(value: scenario) { chip(scenario) }
                    .buttonStyle(.pressable)
            }
        }
    }

    private func chip(_ scenario: HadithScenario) -> some View {
        HStack(spacing: 8) {
            Image(systemName: scenario.icon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(scenario.tint)
                .frame(width: 28, height: 28)
                .background(scenario.tint.opacity(0.2), in: .circle)
            Text(scenario.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.leading, 5)
        .padding(.trailing, 14)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(scenario.tint.opacity(0.12))
                .strokeBorder(scenario.tint.opacity(0.3), lineWidth: 1)
        }
    }
}

/// Lays its children out in centred lines, starting a new line when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            // Each line centred, like the opening lines of the mushaf.
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].items.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.items.isEmpty }
    }
}

/// The top-level topics, one row each, with how many hadiths each holds.
struct TopicGrid: View {
    let topics: [HadithTopic]
    let index: HadithIndex

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(topics.enumerated()), id: \.element.id) { position, topic in
                if position > 0 { Divider().overlay(Palette.hairline).padding(.leading, 66) }
                NavigationLink(value: topic) {
                    HStack(spacing: 14) {
                        Image(systemName: topic.icon)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.highlight)
                            .frame(width: 38, height: 38)
                            .background(Palette.highlight.opacity(0.14), in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(topic.title)
                                .font(.body.weight(.semibold))
                                .multilineTextAlignment(.leading)
                            Text("\(index.hadiths(in: topic).count.formatted()) hadiths")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(.rect)
                }
                .buttonStyle(.pressable)
            }
        }
        .surface(cornerRadius: 22)
    }
}

/// Subtopics, as a plain list.
struct TopicList: View {
    let topics: [HadithTopic]
    let index: HadithIndex

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(topics.enumerated()), id: \.element.id) { position, topic in
                if position > 0 { Divider().overlay(Palette.hairline).padding(.leading, 16) }
                NavigationLink(value: topic) {
                    HStack {
                        Text(topic.title).font(.body).multilineTextAlignment(.leading)
                        Spacer()
                        Text("\(index.hadiths(in: topic).count)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(.rect)
                }
                .buttonStyle(.pressable)
            }
        }
        .surface(cornerRadius: 20)
    }
}

/// A list of hadiths: a gold edge, the title, a line of the explanation, grade and source.
struct HadithRows: View {
    let hadiths: [Hadith]

    var body: some View {
        ForEach(hadiths) { hadith in
            NavigationLink(value: hadith) {
                HStack(alignment: .top, spacing: 14) {
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.highlight, Palette.accent.opacity(0.4)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(hadith.title)
                            .font(.body.weight(.semibold))
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                        if !hadith.explanation.isEmpty {
                            Text(hadith.explanation)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        HStack(spacing: 8) {
                            GradeBadge(level: hadith.level)
                            Text(hadith.source).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(.white)
                .padding(16)
                .surface(cornerRadius: 20)
            }
            .buttonStyle(.pressable)
        }
    }
}

/// Where the hadiths come from and what "Sahih" and "Hasan" mean, centred.
struct AuthenticityNote: View {
    let version: String
    let count: Int

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title2)
                .foregroundStyle(Palette.highlight)
            Text("Only authentic hadiths").font(.subheadline.weight(.semibold))
            Text("\(count.formatted()) hadiths of the Prophet ﷺ graded Sahih or Hasan by the scholars of the Encyclopedia of Translated Prophetic Hadiths. Weak hadiths, sayings of Companions and partly authentic narrations are left out.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("From \(version)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.hairline))
    }
}

/// A section heading. Without a count it's centred between two small
/// ornaments; with one, the count sits on the right.
struct HadithSectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        Group {
            if let trailing {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).sectionLabelStyle()
                    Spacer()
                    Text(trailing).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 10) {
                    rule
                    EightPointStar().fill(Palette.highlight.opacity(0.7)).frame(width: 7, height: 7)
                    Text(title).sectionLabelStyle().fixedSize()
                    EightPointStar().fill(Palette.highlight.opacity(0.7)).frame(width: 7, height: 7)
                    rule.scaleEffect(x: -1, y: 1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 10)
    }

    private var rule: some View {
        Rectangle()
            .fill(LinearGradient(colors: [.clear, Palette.highlight.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
            .frame(width: 36, height: 1)
    }
}

/// The top of the Hadith tab: ﷺ, the name, and a line saying what's here.
struct HadithPageHeader: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(uiImage: SalawatIcon.large)
                .foregroundStyle(Palette.highlight)
                .accessibilityHidden(true)
            Text("Hadith")
                .font(.display(34, weight: .heavy))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text("The words of the Prophet ﷺ, authentic and explained")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            OrnamentDivider().frame(width: 130).padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}
