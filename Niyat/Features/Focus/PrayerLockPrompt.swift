import SwiftUI

/// When to ask "Have you prayed?" as Niyat opens during a Prayer Lock.
/// Pure logic (no Screen Time), so it's tested.
enum PrayerLockPrompt {
    /// "Not yet" keeps it away this long.
    static let snooze: TimeInterval = 5 * 60
    static let snoozeKey = "focus.promptSnoozedUntil"

    static func shouldShow(lockedUntil: Date?, snoozedUntil: Date?, now: Date) -> Bool {
        guard let lockedUntil, lockedUntil > now else { return false }
        return snoozedUntil.map { now >= $0 } ?? true
    }
}

#if SCREEN_TIME
/// Shown over the app while apps are locked for a prayer: unlock them by
/// saying you've prayed (which also logs it), or carry on and come back.
struct PrayerLockSheet: View {
    let prayer: PrayerName?
    let until: Date
    let onPrayed: () -> Void
    let onNotYet: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(Palette.highlight.opacity(0.14)).frame(width: 120, height: 120)
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Palette.highlight)
            }
            .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(prayer.map { "It's time for \($0.displayName(on: .now))" } ?? "Your apps are locked")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                if let prayer {
                    Text(prayer.arabicName)
                        .font(.quran(size: 34))
                        .foregroundStyle(Palette.highlight)
                }
                Text("Your apps are locked until \(until.shortTime). Pray, then unlock them here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                Button(action: onPrayed) {
                    Label(prayer == nil ? "Unlock my apps" : "I've prayed, unlock my apps", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.control)
                .controlSize(.large)
                Button("Not yet", action: onNotYet)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
            }
            if prayer != nil {
                Text("Unlocking marks \(prayer?.displayName(on: .now) ?? "the prayer") as prayed on time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .readableWidth(480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .niyatBackground()
        .interactiveDismissDisabled()
    }
}

/// Asks as the app opens (and when a lock starts while it's open).
struct PrayerLockPromptModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var lock: (prayer: PrayerName?, until: Date)?

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase, initial: true) { _, phase in if phase == .active { check() } }
            // A lock can start while Niyat is open: look again each minute.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    check()
                }
            }
            .fullScreenCover(isPresented: Binding(get: { lock != nil }, set: { if !$0 { lock = nil } })) {
                if let lock {
                    PrayerLockSheet(prayer: lock.prayer, until: lock.until, onPrayed: { prayed(lock.prayer) }, onNotYet: notYet)
                }
            }
            .haptic(.success, trigger: lock == nil) { old, new in !old && new }
    }

    private func check() {
        let snoozed = UserDefaults.standard.object(forKey: PrayerLockPrompt.snoozeKey) as? Date
        guard lock == nil,
              PrayerLockPrompt.shouldShow(lockedUntil: FocusStore.lockedUntil, snoozedUntil: snoozed, now: .now),
              let until = FocusStore.lockedUntil else { return }
        lock = (FocusStore.activePrayer, until)
    }

    private func prayed(_ prayer: PrayerName?) {
        FocusScheduler.endCurrentLock()
        if let prayer, prayer.isObligatory, model.record(for: prayer, on: .now) == nil {
            model.setRecord(PrayerRecord(status: .onTime, reason: nil), for: prayer, on: .now)
        }
        UserDefaults.standard.removeObject(forKey: PrayerLockPrompt.snoozeKey)
        lock = nil
    }

    private func notYet() {
        UserDefaults.standard.set(Date.now.addingTimeInterval(PrayerLockPrompt.snooze), forKey: PrayerLockPrompt.snoozeKey)
        lock = nil
    }
}
#endif
