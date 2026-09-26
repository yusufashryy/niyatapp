import StoreKit
import SwiftUI

/// Optional one-time tips through Apple's In-App Purchase, to help cover the
/// cost of keeping Niyat on the App Store. Nothing is unlocked by tipping:
/// every feature stays free for everyone.
///
/// The three products are "consumable" in-app purchases, set up in App Store
/// Connect with these IDs. `Config/Niyat.storekit` lets you test them in
/// Xcode before that (no real money is charged).
@MainActor
@Observable
final class TipJar {
    static let shared = TipJar()
    static let productIDs = ["niyat.tip.small", "niyat.tip.medium", "niyat.tip.large"]

    enum State: Equatable {
        case idle, purchasing, thanked
        case failed(String)
    }

    private(set) var products: [Product] = []
    private(set) var isLoading = false
    var state = State.idle
    @ObservationIgnored private var updates: Task<Void, Never>?

    private init() {}

    /// Finishes tips that complete later (e.g. after "Ask to Buy" approval).
    /// Call once at launch.
    func startListening() {
        guard updates == nil else { return }
        updates = Task {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
            }
        }
    }

    func load() async {
        guard products.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        products = ((try? await Product.products(for: Self.productIDs)) ?? []).sorted { $0.price < $1.price }
    }

    /// Amounts a custom tip can be: each tip bought 1–10 times at once (Apple
    /// doesn't allow arbitrary amounts, but does allow a quantity).
    var customAmounts: [CustomAmount] {
        var seen = Set<Decimal>()
        var result: [CustomAmount] = []
        for product in products {
            for quantity in 1...10 {
                let total = product.price * Decimal(quantity)
                guard seen.insert(total).inserted else { continue }
                result.append(CustomAmount(product: product, quantity: quantity, total: total))
            }
        }
        return result.sorted { $0.total < $1.total }
    }

    struct CustomAmount: Hashable {
        let product: Product
        let quantity: Int
        let total: Decimal

        var displayTotal: String { total.formatted(product.priceFormatStyle) }
    }

    func buy(_ product: Product, quantity: Int = 1) async {
        state = .purchasing
        do {
            switch try await product.purchase(options: quantity > 1 ? [.quantity(quantity)] : []) {
            case .success(.verified(let transaction)):
                await transaction.finish()
                UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "support.tips") + 1, forKey: "support.tips")
                state = .thanked
            case .success(.unverified):
                state = .failed("Apple couldn't verify that purchase, so nothing was charged.")
            case .pending:
                state = .idle
            case .userCancelled:
                state = .idle
            @unknown default:
                state = .idle
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct SupportView: View {
    @State private var jar = TipJar.shared
    @AppStorage("support.tips") private var tipCount = 0
    @State private var customIndex = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                    .appearAnimation(0)
                costs
                    .appearAnimation(1)
                tips
                    .appearAnimation(2)
                Text("Tips are processed by Apple. Niyat never sees your payment details. After Apple's fee, every tip goes towards running and improving the app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(16)
        }
        .niyatBackground()
        .navigationTitle("Support Niyat")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await jar.load()
            // Start the custom picker a step above the fixed tips.
            customIndex = jar.customAmounts.firstIndex { $0.total >= 15 } ?? 0
        }
        .overlay {
            if jar.state == .thanked {
                thankYou
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.bouncy, value: jar.state)
    }

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                Rosette(color: Palette.highlight.opacity(0.3), lineWidth: 1)
                    .frame(width: 130, height: 130)
                Image(systemName: "heart.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Palette.highlight)
                    .frame(width: 76, height: 76)
                    .glassEffect(.regular.tint(Palette.glow.opacity(0.5)), in: .circle)
            }
            Text("Free forever")
                .font(.display(28, weight: .heavy))
            Text("Niyat has no ads, no subscriptions, no accounts and no tracking, and every feature is free for everyone. If it helps you, you can help keep it running.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
            if tipCount > 0 {
                Label("You've supported Niyat. Jazak Allahu khayran!", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.highlight)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .glassPanel(cornerRadius: 30, tint: Palette.glow.opacity(0.35))
    }

    private var costs: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What it costs").sectionLabelStyle()
            costRow("Apple Developer Program", detail: "Needed to be on the App Store", value: "$99 / year")
            costRow("Servers", detail: "None: everything runs on your phone", value: "$0")
            costRow("Recitation audio", detail: "Islamic Network's free CDN", value: "$0")
            costRow("Groups", detail: "Apple iCloud", value: "$0")
        }
        .padding(18)
        .surface(cornerRadius: 22)
    }

    private func costRow(_ title: String, detail: String, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value).font(.subheadline.monospacedDigit().weight(.semibold))
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var tips: some View {
        VStack(spacing: 10) {
            if jar.products.isEmpty {
                if jar.isLoading {
                    ProgressView()
                } else {
                    Label("Tips aren't available right now. Please try again later.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(jar.products, id: \.id) { product in
                    Button {
                        Task { await jar.buy(product) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.displayName).font(.headline)
                                if !product.description.isEmpty {
                                    Text(product.description).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(product.displayPrice)
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Palette.accent, in: .capsule)
                        }
                        .foregroundStyle(.white)
                        .padding(16)
                        .surface(cornerRadius: 20)
                    }
                    .buttonStyle(.pressable)
                    .disabled(jar.state == .purchasing)
                }
            }
            if !jar.products.isEmpty {
                customTip
            }
            if case .failed(let message) = jar.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Pick any amount from the list, then tip it in one go.
    private var customTip: some View {
        let amounts = jar.customAmounts
        let index = min(customIndex, max(amounts.count - 1, 0))
        return VStack(alignment: .leading, spacing: 12) {
            Text("Custom amount").font(.headline)
            if let amount = amounts[safe: index] {
                HStack {
                    Button {
                        customIndex = max(index - 1, 0)
                    } label: {
                        Image(systemName: "minus").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .disabled(index == 0)
                    Spacer()
                    Text(amount.displayTotal)
                        .font(.display(30, weight: .heavy).monospacedDigit())
                        .contentTransition(.numericText(value: NSDecimalNumber(decimal: amount.total).doubleValue))
                        .animation(.smooth, value: index)
                    Spacer()
                    Button {
                        customIndex = min(index + 1, amounts.count - 1)
                    } label: {
                        Image(systemName: "plus").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .disabled(index >= amounts.count - 1)
                }
                .haptic(.selection, trigger: index)
                Button {
                    Task { await jar.buy(amount.product, quantity: amount.quantity) }
                } label: {
                    Text("Tip \(amount.displayTotal)")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.control)
                .controlSize(.large)
                .disabled(jar.state == .purchasing)
                Text("Apple doesn't allow typing in any amount, so custom tips are made of the tips above, up to 10 at once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .surface(cornerRadius: 20)
    }

    private var thankYou: some View {
        VStack(spacing: 12) {
            EightPointStar()
                .fill(Palette.highlight)
                .frame(width: 50, height: 50)
                .shadow(color: Palette.highlight, radius: 14)
            Text("Thank you!")
                .font(.display(26, weight: .heavy))
            Text("جزاك الله خيرا")
                .font(.calligraphy(size: 28))
                .foregroundStyle(Palette.highlight)
            Text("May Allah reward you with good.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(28)
        .glassPanel(cornerRadius: 32, tint: Palette.glow.opacity(0.4))
        .padding(40)
        .onTapGesture { jar.state = .idle }
        .task {
            try? await Task.sleep(for: .seconds(3))
            if jar.state == .thanked { jar.state = .idle }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
