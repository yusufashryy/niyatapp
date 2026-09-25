import SwiftUI

/// "Use my location" plus a city search. Used in onboarding and Settings.
struct LocationPickerView: View {
    enum Style { case onboarding, settings }

    let style: Style
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
                    if isLocating { ProgressView().tint(buttonForeground) } else { Image(systemName: "location.fill") }
                    Text("Use my current location")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(buttonBackground, in: .rect(cornerRadius: 14))
                .foregroundStyle(buttonForeground)
            }
            .disabled(isLocating)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Or search for a city", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                if isSearching { ProgressView() }
            }
            .padding(12)
            .background(.background, in: .rect(cornerRadius: 12))
            .foregroundStyle(.primary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(style == .onboarding ? Color.white : Color.red)
            }

            ForEach(results, id: \.self) { result in
                Button {
                    onPick(result)
                } label: {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                        Text(result.name).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote)
                    }
                    .padding(12)
                    .background(.background.opacity(0.9), in: .rect(cornerRadius: 12))
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    private var buttonBackground: Color { style == .onboarding ? .niyatiGold : .niyatiGreen }
    private var buttonForeground: Color { style == .onboarding ? .niyatiDeepGreen : .white }

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
