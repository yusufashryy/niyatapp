import SwiftUI

/// "Use my location" plus a city search. Used in onboarding and Settings.
struct LocationPickerView: View {
    let onPick: (SavedLocation) -> Void

    @State private var query = ""
    @State private var results: [SavedLocation] = []
    @State private var isLocating = false
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 14) {
            Button {
                Task { await useCurrentLocation() }
            } label: {
                HStack {
                    if isLocating { ProgressView().tint(.black) } else { Image(systemName: "location.fill") }
                    Text("Use my current location")
                }
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.accent)
            .controlSize(.extraLarge)
            .disabled(isLocating)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Or search for a city", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                if isSearching { ProgressView() }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .glassEffect(.regular.interactive(), in: .capsule)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.orange)
            }

            ForEach(results, id: \.self) { result in
                Button {
                    onPick(result)
                } label: {
                    HStack {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(Palette.accent)
                        Text(result.name)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .surface(cornerRadius: 18)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private func useCurrentLocation() async {
        isLocating = true
        errorMessage = nil
        defer { isLocating = false }
        do {
            onPick(try await LocationService.shared.currentSavedLocation())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            results = try await LocationService.search(trimmed)
            if results.isEmpty { errorMessage = "No places found for “\(trimmed)”." }
        } catch {
            results = []
            errorMessage = "No places found for “\(trimmed)”."
        }
    }
}
