import SwiftUI

#if SCREEN_TIME
import FamilyControls

/// Prayer Lock: blocks the apps you choose from the adhan until you've had time to pray.
struct FocusView: View {
    @Environment(AppModel.self) private var model
    @State private var settings = FocusStore.settings
    @State private var selection = FocusStore.selection
    @State private var isPickerPresented = false
    @State private var authorization = AuthorizationCenter.shared.authorizationStatus
    @State private var errorMessage: String?
    @State private var manualMinutes = 30

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Form {
                    FocusIntroSection()

                    if authorization != .approved {
                        Section {
                            Button("Allow Screen Time access") {
                                Task { await requestAuthorization() }
                            }
                        } footer: {
                            Text("Salah needs Screen Time permission to lock apps. Nothing leaves your phone. Apple doesn't even tell Salah which apps you pick.")
                        }
                    } else {
                        if FocusScheduler.isLocked, let until = FocusStore.lockedUntil, until > context.date {
                            activeLockSection(until: until)
                        }
                        lockSettingsSection
                        manualLockSection
                    }

                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle("Prayer Lock")
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
            .onChange(of: selection) { _, new in
                FocusStore.selection = new
                FocusScheduler.reschedule()
            }
            .onChange(of: settings) { _, new in
                FocusStore.settings = new
                FocusScheduler.reschedule()
            }
            .onAppear { authorization = AuthorizationCenter.shared.authorizationStatus }
        }
    }

    private var selectionSummary: String {
        let apps = selection.applicationTokens.count
        let categories = selection.categoryTokens.count
        let sites = selection.webDomainTokens.count
        if apps + categories + sites == 0 { return "None chosen" }
        var parts: [String] = []
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if categories > 0 { parts.append("\(categories) categor\(categories == 1 ? "y" : "ies")") }
        if sites > 0 { parts.append("\(sites) site\(sites == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }

    private func activeLockSection(until: Date) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(FocusStore.activePrayer.map { "Locked for \($0.englishName)" } ?? "Locked")
                    .font(.headline)
                Text("Unlocks at \(until.shortTime)")
                    .foregroundStyle(.secondary)
            }
            Button {
                FocusScheduler.endCurrentLock()
            } label: {
                Label("I've prayed, unlock now", systemImage: "checkmark.seal.fill")
            }
        }
    }

    private var lockSettingsSection: some View {
        Section {
            Toggle("Lock apps at prayer times", isOn: $settings.isEnabled)
            Button {
                isPickerPresented = true
            } label: {
                LabeledContent("Apps to lock", value: selectionSummary)
            }
            Stepper(value: $settings.minutes, in: 15...90, step: 5) {
                LabeledContent("Lock for", value: "\(settings.minutes) min")
            }
            ForEach(PrayerName.obligatory) { prayer in
                Toggle(prayer.englishName, isOn: Binding(
                    get: { settings.prayers.contains(prayer) },
                    set: { isOn in
                        if isOn { settings.prayers.insert(prayer) } else { settings.prayers.remove(prayer) }
                    }
                ))
            }
        } header: {
            Text("At prayer time")
        } footer: {
            Text("When the adhan time comes, the apps you choose are locked for \(settings.minutes) minutes. Apple requires at least 15. Tap “I've prayed” here to unlock early.")
        }
    }

    private var manualLockSection: some View {
        Section {
            Stepper(value: $manualMinutes, in: 15...180, step: 15) {
                LabeledContent("Duration", value: "\(manualMinutes) min")
            }
            Button("Lock now") {
                do {
                    try FocusScheduler.startManualLock(minutes: manualMinutes)
                    errorMessage = nil
                } catch {
                    errorMessage = "Couldn't start the lock: \(error.localizedDescription)"
                }
            }
            .disabled(selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty && selection.webDomainTokens.isEmpty)
        } header: {
            Text("Focus session")
        } footer: {
            Text("Lock the same apps right now, e.g. while you read Quran or do your adhkar.")
        }
    }

    private func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            errorMessage = nil
        } catch {
            errorMessage = "Screen Time permission wasn't granted: \(error.localizedDescription)"
        }
        authorization = AuthorizationCenter.shared.authorizationStatus
    }
}

#else

/// Shown when the app is built without Screen Time (free Apple account).
struct FocusView: View {
    var body: some View {
        NavigationStack {
            Form {
                FocusIntroSection()
                Section {
                    Label("Not available in this build", systemImage: "lock.slash")
                        .font(.headline)
                    Text("Apple only lets apps lock other apps with the Screen Time permission, which needs a paid Apple Developer account ($99/year). If you have one, build with `make full` instead of `make`. The README has the steps.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Prayer Lock")
        }
    }
}

#endif

private struct FocusIntroSection: View {
    var body: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.salahGold)
                Text("Put the phone down when it's time to pray. Prayer Lock blocks distracting apps at each adhan.")
                    .font(.subheadline)
            }
            .padding(.vertical, 6)
        }
    }
}
