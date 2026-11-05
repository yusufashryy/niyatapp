import SwiftUI

/// Automatic mode moved the prayer times: "Updated for Chicago · Undo".
struct LocationUpdatedBanner: View {
    @Environment(AppModel.self) private var model
    let change: LocationChange

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.fill")
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Updated for \(change.current.shortName)")
                    .font(.subheadline.weight(.semibold))
                Text("You were in \(change.previous.shortName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Undo") {
                withAnimation(.smooth) { model.undoLocationChange() }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.glass)
            Button {
                withAnimation(.smooth) { model.recentLocationChange = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .surface(cornerRadius: 22)
        .haptic(.success, trigger: change)
    }
}

/// Manual mode, but the device's clock is on another time zone: ask before moving.
struct TimeZoneChangedCard: View {
    @Environment(AppModel.self) private var model
    let location: SavedLocation
    @State private var isLocating = false
    @State private var showPicker = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Update prayer times?")
                    .font(.headline)
                Text("Your device's clock is on a different time zone from \(location.name). If you've travelled, Niyat can show times for where you are now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 10) {
                Button {
                    Task { await update() }
                } label: {
                    HStack {
                        if isLocating { ProgressView().tint(.black) }
                        Text("Update")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.accent)
                .controlSize(.large)
                .disabled(isLocating)

                Button {
                    withAnimation(.smooth) { model.dismissTimeZonePrompt() }
                } label: {
                    Text("Keep \(location.shortName)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
        .padding(18)
        .surface(cornerRadius: 26)
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                ScrollView {
                    LocationPickerView { picked, mode in
                        model.setLocation(picked, mode: mode)
                        showPicker = false
                    }
                    .padding()
                    .readableWidth()
                }
                .niyatBackground()
                .navigationTitle("Location")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { showPicker = false } }
                }
            }
        }
    }

    /// With location access, updates straight away. Without it, opens the picker
    /// so the user can search for the city or choose to share their location.
    private func update() async {
        guard LocationService.shared.isAuthorized else {
            showPicker = true
            return
        }
        isLocating = true
        errorMessage = nil
        defer { isLocating = false }
        do {
            let current = try await LocationService.shared.currentSavedLocation()
            withAnimation(.smooth) { model.setLocation(current, mode: .automatic) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
