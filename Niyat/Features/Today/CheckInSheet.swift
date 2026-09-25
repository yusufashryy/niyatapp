import SwiftUI
import UIKit

/// Identifies one prayer on one day, for presenting the check-in sheet.
struct PrayerSlot: Identifiable, Hashable {
    let prayer: PrayerName
    let day: Date

    var id: String { PrayerLog.key(prayer, on: day) }
}

/// "How did Asr go?": one tap for on time, or pick late/missed and why.
struct CheckInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let slot: PrayerSlot

    @State private var status: PrayerStatus?
    @State private var reason: MissReason?

    private let reasonColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 4) {
                    Text(slot.prayer.arabicName)
                        .font(.calligraphy(size: 44))
                        .foregroundStyle(Palette.highlight)
                    Text("How did \(slot.prayer.displayName(on: slot.day)) go?")
                        .font(.title2.weight(.bold))
                    Text(slot.day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                Button {
                    save(PrayerRecord(status: .onTime))
                } label: {
                    Label("Prayed on time", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.accent)
                .controlSize(.extraLarge)

                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        statusButton(.late)
                        statusButton(.missed)
                        statusButton(.excused)
                    }
                }

                if let status, status.asksForReason {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(status == .late ? "What made it late?" : "What got in the way?")
                            .font(.headline)
                        LazyVGrid(columns: reasonColumns, spacing: 10) {
                            ForEach(MissReason.allCases) { option in
                                reasonButton(option)
                            }
                        }
                        Button {
                            save(PrayerRecord(status: status, reason: reason))
                        } label: {
                            Text("Save")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .padding(.top, 4)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if model.record(for: slot.prayer, on: slot.day) != nil {
                    Button("Clear", role: .destructive) { save(nil) }
                        .font(.subheadline)
                }

                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .animation(.smooth(duration: 0.35), value: status)
        .haptic(.selection, trigger: status)
        .haptic(.selection, trigger: reason)
        .onAppear {
            let existing = model.record(for: slot.prayer, on: slot.day)
            status = existing?.status
            reason = existing?.reason
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var footnote: String {
        switch status {
        case .excused: "Excused prayers (travel shortening, illness, menstruation) don't break your streak."
        case .missed: "May Allah make it easy. You can make it up as qada."
        default: "Only you can see this. It never leaves your phone."
        }
    }

    private func statusButton(_ option: PrayerStatus) -> some View {
        Button {
            if option.asksForReason {
                status = option
            } else {
                save(PrayerRecord(status: option))
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: option.symbolName)
                    .font(.title2)
                Text(option.title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(status == option ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassEffect(status == option ? .regular.tint(option.color).interactive() : .regular.interactive(),
                         in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.pressable)
    }

    private func reasonButton(_ option: MissReason) -> some View {
        Button {
            reason = reason == option ? nil : option
        } label: {
            Label(option.title, systemImage: option.symbolName)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .foregroundStyle(reason == option ? .black : .white)
                .background(reason == option ? Palette.highlight : Color.white.opacity(0.07), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.pressable)
    }

    private func save(_ record: PrayerRecord?) {
        withAnimation(.bouncy) { model.setRecord(record, for: slot.prayer, on: slot.day) }
        if let record, Haptics.isEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(record.status == .missed ? .warning : .success)
        }
        dismiss()
    }
}

extension PrayerStatus {
    /// Colour used for this status in rows, the dial and the calendar.
    var color: Color {
        switch self {
        case .onTime: Palette.accent
        case .late: Palette.highlight
        case .missed: Color(red: 0.97, green: 0.45, blue: 0.45)
        case .excused: Color.white.opacity(0.55)
        }
    }
}
