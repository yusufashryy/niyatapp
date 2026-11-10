import SwiftUI

/// Authentic hadiths: today's hadith, everyday situations, topics, and search.
struct HadithListView: View {
    @State private var library = HadithLibrary.shared
    @State private var query = ""
    @State private var sharing: QuranShareContent?
    @State private var deepLink = DeepLink.shared
    /// A hadith opened from its notification.
    @State private var opened: Hadith?
    @State private var showNotifications = false
    @State private var saved = SavedHadiths.shared
    /// The last finished search: what was searched for and what it found.
    @State private var search: (query: String, results: [Hadith])?

    /// How long typing must pause before the hadiths are searched.
    private static let searchPause: Duration = .milliseconds(250)

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Group {
            if let index = library.index {
                content(index)
            } else if let error = library.loadError {
                ContentUnavailableView("Hadiths unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .niyatBackground()
        // The page draws its own centred header; the bar keeps the name for
        // the back button and VoiceOver.
        .navigationTitle("Hadith")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) } }
        .searchable(text: $query, prompt: "A word or a situation")
        // Registered here, outside the content that loads, so they stay put.
        .navigationDestination(for: Hadith.self) { HadithDetailView(hadith: $0) }
        .navigationDestination(for: HadithTopic.self) { HadithTopicView(topic: $0) }
        .navigationDestination(for: HadithScenario.self) { HadithScenarioView(scenario: $0) }
        .navigationDestination(item: $opened) { HadithDetailView(hadith: $0) }
        .navigationDestination(for: HadithRoute.self) { _ in SavedHadithsView() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNotifications = true } label: { Image(systemName: "bell.badge") }
                    .accessibilityLabel("Hadith notifications")
            }
        }
        .sheet(isPresented: $showNotifications) { HadithNotificationSheet() }
        .task(id: deepLink.pending) {
            guard case .hadith(let id)? = deepLink.pending, let index = await library.load() else { return }
            deepLink.pending = nil
            opened = index.hadiths.first { $0.id == id }
        }
        .task { await library.load() }
        // Searches once typing pauses, off the main thread, so typing stays smooth.
        .task(id: trimmedQuery) {
            let text = trimmedQuery
            guard !text.isEmpty else { search = nil; return }
            try? await Task.sleep(for: Self.searchPause)
            guard !Task.isCancelled, let index = await library.load() else { return }
            let results = await Task.detached(priority: .userInitiated) { index.search(text) }.value
            guard !Task.isCancelled else { return }
            search = (text, results)
        }
    }

    @ViewBuilder
    private func content(_ index: HadithIndex) -> some View {
        let trimmed = trimmedQuery
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if trimmed.isEmpty {
                    HadithPageHeader()
                    if let today = index.hadithOfTheDay() {
                        NavigationLink(value: today) {
                            HadithOfTheDayCard(hadith: today) { sharing = .hadith(today) }
                        }
                        .buttonStyle(.pressable)
                        .appearAnimation(0)
                    }
                    TrustStrip(count: index.hadiths.count)
                        .appearAnimation(1)
                    if !saved.ids.isEmpty {
                        NavigationLink(value: HadithRoute.saved) {
                            HStack(spacing: 14) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(Palette.highlight)
                                    .frame(width: 38, height: 38)
                                    .background(Palette.highlight.opacity(0.14), in: .circle)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Saved hadiths").font(.body.weight(.semibold))
                                    Text("\(saved.ids.count) saved").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .surface(cornerRadius: 22)
                        }
                        .buttonStyle(.pressable)
                    }
                    HadithSectionHeader(title: "Find by situation")
                    ScenarioCloud()
                        .appearAnimation(2)
                    HadithSectionHeader(title: "Topics")
                    TopicGrid(topics: index.rootTopics, index: index)
                        .appearAnimation(3)
                    AuthenticityNote(version: index.file.version, count: index.hadiths.count)
                        .padding(.top, 12)
                } else if let search {
                    // The last results stay up while the next search runs.
                    if search.results.isEmpty {
                        ContentUnavailableView.search(text: search.query)
                    } else {
                        HadithSectionHeader(title: "Results",
                                            trailing: "\(search.results.count) hadith\(search.results.count == 1 ? "" : "s")")
                        HadithRows(hadiths: search.results)
                    }
                } else {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(16)
            .readableWidth()
        }
        .sheet(item: $sharing) { QuranShareSheet(content: $0) }
    }
}

/// A topic: its subtopics, then its hadiths.
struct HadithTopicView: View {
    let topic: HadithTopic
    @State private var library = HadithLibrary.shared

    var body: some View {
        ScrollView {
            if let index = library.index {
                LazyVStack(alignment: .leading, spacing: 12) {
                    let children = index.subtopics(of: topic)
                    if !children.isEmpty {
                        TopicList(topics: children, index: index)
                    }
                    let hadiths = index.hadiths(in: topic)
                    HadithSectionHeader(title: "Hadiths", trailing: "\(hadiths.count)")
                    HadithRows(hadiths: hadiths)
                }
                .padding(16)
                .readableWidth()
            }
        }
        .niyatBackground()
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The hadiths about one everyday situation.
struct HadithScenarioView: View {
    let scenario: HadithScenario
    @State private var library = HadithLibrary.shared

    var body: some View {
        ScrollView {
            if let index = library.index {
                LazyVStack(alignment: .leading, spacing: 12) {
                    let hadiths = index.search(scenario)
                    HStack(spacing: 12) {
                        Image(systemName: scenario.icon)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(scenario.tint)
                            .frame(width: 52, height: 52)
                            .background(scenario.tint.opacity(0.18), in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hadiths about \(scenario.title.lowercased())").font(.headline)
                            Text("\(hadiths.count) authentic hadiths, best matches first")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.bottom, 4)
                    HadithRows(hadiths: hadiths)
                }
                .padding(16)
                .readableWidth()
            }
        }
        .niyatBackground()
        .navigationTitle(scenario.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Places in the Hadith tab that aren't a hadith, topic or situation.
enum HadithRoute: Hashable { case saved }

/// The hadiths you've starred, newest first.
struct SavedHadithsView: View {
    @State private var library = HadithLibrary.shared
    @State private var saved = SavedHadiths.shared

    var body: some View {
        ScrollView {
            if let index = library.index {
                let hadiths = saved.hadiths(in: index)
                if hadiths.isEmpty {
                    ContentUnavailableView("No saved hadiths", systemImage: "star",
                                           description: Text("Tap the star on a hadith to keep it here."))
                        .padding(.top, 60)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        HadithRows(hadiths: hadiths)
                    }
                    .padding(16)
                    .readableWidth()
                }
            }
        }
        .niyatBackground()
        .navigationTitle("Saved hadiths")
        .navigationBarTitleDisplayMode(.inline)
    }
}
