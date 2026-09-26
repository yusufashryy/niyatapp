import SwiftUI
import UIKit

/// A supplication found in the Qur'an. Only the reference is stored here: the
/// Arabic and English are always read from the bundled, verified text, so
/// nothing is retyped. Each entry is checked against the text in the tests.
struct QuranicDua: Identifiable, Hashable {
    let surah: Int
    let verses: ClosedRange<Int>
    /// What it asks for, in a few words.
    let title: String
    /// Who made the dua, as told in the Qur'an.
    let context: String

    var id: String { "\(surah):\(verses.lowerBound)" }
    var reference: String {
        verses.count == 1 ? "\(surah):\(verses.lowerBound)" : "\(surah):\(verses.lowerBound)–\(verses.upperBound)"
    }

    enum Category: String, CaseIterable, Identifiable {
        case forgiveness = "Forgiveness and mercy"
        case guidance = "Guidance and steadfastness"
        case bothWorlds = "This life and the next"
        case family = "Family and children"
        case knowledge = "Knowledge, ease and gratitude"
        case protection = "Help and protection"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .forgiveness: "heart.fill"
            case .guidance: "sparkles"
            case .bothWorlds: "sun.and.horizon.fill"
            case .family: "figure.2.and.child.holdinghands"
            case .knowledge: "book.fill"
            case .protection: "shield.fill"
            }
        }
    }

    struct DuaGroup: Identifiable {
        let category: Category
        let duas: [QuranicDua]
        var id: Category { category }

        init(_ category: Category, _ duas: [QuranicDua]) {
            self.category = category
            self.duas = duas
        }
    }

    static let all: [DuaGroup] = [
        DuaGroup(.forgiveness, [
            QuranicDua(surah: 7, verses: 23...23, title: "We have wronged ourselves", context: "Adam and Hawwa"),
            QuranicDua(surah: 21, verses: 87...87, title: "There is no god but You", context: "Prophet Yunus, in the belly of the whale"),
            QuranicDua(surah: 28, verses: 16...16, title: "I have wronged myself, so forgive me", context: "Prophet Musa"),
            QuranicDua(surah: 7, verses: 151...151, title: "Forgive me and my brother", context: "Prophet Musa"),
            QuranicDua(surah: 11, verses: 47...47, title: "Forgive me and have mercy on me", context: "Prophet Nuh"),
            QuranicDua(surah: 71, verses: 28...28, title: "Forgive me, my parents and the believers", context: "Prophet Nuh"),
            QuranicDua(surah: 14, verses: 41...41, title: "Forgive me, my parents and the believers", context: "Prophet Ibrahim"),
            QuranicDua(surah: 3, verses: 16...16, title: "We have believed, so forgive us", context: "The righteous"),
            QuranicDua(surah: 3, verses: 147...147, title: "Forgive our sins and make our feet firm", context: "Those who fought alongside the prophets"),
            QuranicDua(surah: 23, verses: 109...109, title: "Forgive us and have mercy on us", context: "A group of Allah's servants"),
            QuranicDua(surah: 23, verses: 118...118, title: "Forgive and have mercy", context: "Taught to the Prophet ﷺ"),
            QuranicDua(surah: 59, verses: 10...10, title: "Forgive us and our brothers in faith", context: "The believers who came after"),
            QuranicDua(surah: 2, verses: 286...286, title: "Do not burden us beyond what we can bear", context: "The believers"),
        ]),
        DuaGroup(.guidance, [
            QuranicDua(surah: 3, verses: 8...8, title: "Do not let our hearts deviate", context: "Those firmly grounded in knowledge"),
            QuranicDua(surah: 2, verses: 250...250, title: "Pour patience upon us", context: "Talut's army before facing Jalut"),
            QuranicDua(surah: 7, verses: 126...126, title: "Pour patience upon us and let us die as Muslims", context: "Pharaoh's magicians after believing"),
            QuranicDua(surah: 18, verses: 10...10, title: "Grant us mercy and guide our affair", context: "The youths of the cave"),
            QuranicDua(surah: 3, verses: 53...53, title: "Write us among the witnesses", context: "The disciples of Prophet Isa"),
            QuranicDua(surah: 5, verses: 83...83, title: "We believe, so write us among the witnesses", context: "Those moved to tears by the Qur'an"),
            QuranicDua(surah: 10, verses: 85...86, title: "Do not make us a trial for the wrongdoers", context: "The people of Musa"),
            QuranicDua(surah: 60, verses: 4...5, title: "Upon You we rely, and to You we turn", context: "Prophet Ibrahim and those with him"),
            QuranicDua(surah: 66, verses: 8...8, title: "Perfect our light for us", context: "The believers on the Day of Judgement"),
        ]),
        DuaGroup(.bothWorlds, [
            QuranicDua(surah: 2, verses: 201...201, title: "Good in this world and good in the next", context: "The believers"),
            QuranicDua(surah: 3, verses: 191...194, title: "Save us from the Fire", context: "People of understanding"),
            QuranicDua(surah: 3, verses: 9...9, title: "You will gather mankind for a certain Day", context: "Those firmly grounded in knowledge"),
            QuranicDua(surah: 25, verses: 65...66, title: "Turn away from us the punishment of Hell", context: "The servants of the Most Merciful"),
            QuranicDua(surah: 7, verses: 47...47, title: "Do not place us with the wrongdoers", context: "The people of the heights (al-A'raf)"),
            QuranicDua(surah: 40, verses: 7...8, title: "Forgive those who repent and admit them to Paradise", context: "The angels who carry the Throne"),
            QuranicDua(surah: 7, verses: 155...156, title: "Decree good for us in this world and the next", context: "Prophet Musa"),
        ]),
        DuaGroup(.family, [
            QuranicDua(surah: 25, verses: 74...74, title: "Grant us comfort in our spouses and children", context: "The servants of the Most Merciful"),
            QuranicDua(surah: 17, verses: 24...24, title: "Have mercy on my parents", context: "Taught for one's parents"),
            QuranicDua(surah: 14, verses: 40...40, title: "Make me and my children keep up the prayer", context: "Prophet Ibrahim"),
            QuranicDua(surah: 14, verses: 35...35, title: "Make this city safe, and keep us from idols", context: "Prophet Ibrahim"),
            QuranicDua(surah: 2, verses: 127...128, title: "Accept this from us, and make us Muslims", context: "Prophets Ibrahim and Isma'il, raising the Ka'bah"),
            QuranicDua(surah: 37, verses: 100...100, title: "Grant me a righteous child", context: "Prophet Ibrahim"),
            QuranicDua(surah: 3, verses: 38...38, title: "Grant me good offspring", context: "Prophet Zakariyya"),
            QuranicDua(surah: 21, verses: 89...89, title: "Do not leave me alone", context: "Prophet Zakariyya"),
            QuranicDua(surah: 3, verses: 35...35, title: "Accept this from me", context: "The wife of 'Imran"),
            QuranicDua(surah: 46, verses: 15...15, title: "Make me grateful, and make my children righteous", context: "One who reaches forty years"),
        ]),
        DuaGroup(.knowledge, [
            QuranicDua(surah: 20, verses: 114...114, title: "My Lord, increase me in knowledge", context: "Taught to the Prophet ﷺ"),
            QuranicDua(surah: 20, verses: 25...28, title: "Expand my chest and ease my task", context: "Prophet Musa"),
            QuranicDua(surah: 26, verses: 83...85, title: "Grant me wisdom and join me with the righteous", context: "Prophet Ibrahim"),
            QuranicDua(surah: 27, verses: 19...19, title: "Enable me to be grateful for Your favour", context: "Prophet Sulayman"),
            QuranicDua(surah: 12, verses: 101...101, title: "Let me die as a Muslim", context: "Prophet Yusuf"),
            QuranicDua(surah: 28, verses: 24...24, title: "I am in need of whatever good You send me", context: "Prophet Musa"),
            QuranicDua(surah: 17, verses: 80...80, title: "Let my entry and exit be truthful", context: "Taught to the Prophet ﷺ"),
            QuranicDua(surah: 23, verses: 29...29, title: "Let me land at a blessed landing place", context: "Prophet Nuh"),
        ]),
        DuaGroup(.protection, [
            QuranicDua(surah: 23, verses: 97...98, title: "I seek refuge in You from the devils", context: "Taught to the Prophet ﷺ"),
            QuranicDua(surah: 21, verses: 83...83, title: "Harm has touched me, and You are the Most Merciful", context: "Prophet Ayyub"),
            QuranicDua(surah: 28, verses: 21...21, title: "Save me from the wrongdoing people", context: "Prophet Musa"),
            QuranicDua(surah: 29, verses: 30...30, title: "Help me against the corrupt", context: "Prophet Lut"),
            QuranicDua(surah: 7, verses: 89...89, title: "Judge between us and our people in truth", context: "Prophet Shu'ayb"),
            QuranicDua(surah: 66, verses: 11...11, title: "Build me a home near You in Paradise", context: "The wife of Pharaoh"),
            QuranicDua(surah: 5, verses: 114...114, title: "Send down a table spread from heaven", context: "Prophet Isa"),
        ]),
    ]
}

/// Qur'an › Duas: supplications from the Qur'an, grouped by theme.
struct QuranicDuasView: View {
    @State private var store = QuranStore.shared
    @State private var player = RecitationPlayer.shared
    @State private var category: QuranicDua.Category?
    let onOpen: (VerseReference) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        chip("All", selected: category == nil) { category = nil }
                        ForEach(QuranicDua.Category.allCases) { item in
                            chip(item.rawValue, selected: category == item) { category = item }
                        }
                    }
                }
                .scrollIndicators(.hidden)

                ForEach(QuranicDua.all.filter { category == nil || $0.category == category }) { group in
                    Label(group.category.rawValue, systemImage: group.category.icon)
                        .sectionLabelStyle()
                        .padding(.top, 6)
                    ForEach(group.duas) { dua in
                        DuaCard(dua: dua, canPlay: store.edition.riwayah.hasVerseAudio,
                                onPlay: { play(dua) }, onOpen: { onOpen(VerseReference(surah: dua.surah, verse: dua.verses.lowerBound)) })
                    }
                }

                Text("Text: Tanzil Project, exactly as in the rest of the app. Translation: The Clear Quran. The note under each dua says who made it, as told in the Qur'an.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .niyatBackground()
        .navigationTitle("Duas from the Qur'an")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            RecitationMiniPlayer().padding(.bottom, 6)
        }
        .haptic(.selection, trigger: category)
        .task { await store.load() }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.smooth) { action() } }) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(selected ? .black : .white)
                .background(selected ? Palette.control : Color.white.opacity(0.08), in: .capsule)
        }
        .buttonStyle(.pressable)
    }

    private func play(_ dua: QuranicDua) {
        player.play(surah: dua.surah, from: dua.verses.lowerBound, verseCounts: store.hafsVerseCounts,
                    only: dua.verses.count == 1)
    }
}

private struct DuaCard: View {
    let dua: QuranicDua
    let canPlay: Bool
    let onPlay: () -> Void
    let onOpen: () -> Void
    @State private var store = QuranStore.shared

    var body: some View {
        let verses = dua.verses.compactMap { store.verse(VerseReference(surah: dua.surah, verse: $0)) }
        let unique = verses.reduce(into: [Verse]()) { list, verse in if !list.contains(verse) { list.append(verse) } }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dua.title).font(.headline)
                    Text(dua.context).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if canPlay {
                    Button(action: onPlay) {
                        Image(systemName: "speaker.wave.2").frame(width: 32, height: 32)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Listen")
                }
            }
            Text(unique.map(\.arabic).joined(separator: " "))
                .font(.quran(size: 24))
                .lineSpacing(10)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundStyle(Palette.highlight)
            Text(unique.map(\.translation).joined(separator: " "))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
            Button(action: onOpen) {
                Label("\(QuranStore.shared.surah(dua.surah)?.transliteration ?? "Surah \(dua.surah)") \(dua.reference)",
                      systemImage: "book")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.pressable)
            .foregroundStyle(Palette.accent)
            .accessibilityHint("Opens the verse in the Qur'an")
        }
        .foregroundStyle(.white)
        .padding(16)
        .surface(cornerRadius: 20)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = "\(unique.map(\.arabic).joined(separator: " "))\n\n\(unique.map(\.translation).joined(separator: " "))\n— Qur'an \(dua.reference)"
            }
        }
    }
}
