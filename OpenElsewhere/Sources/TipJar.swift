import Foundation
import StoreKit

/// StoreKit 2 tip jar for the App Store build.
///
/// Products are **consumable**: a tip can be given repeatedly, and consumables
/// carry no "Restore Purchases" obligation. Nothing is unlocked by a purchase,
/// so there is no entitlement state to persist — the transaction is finished
/// immediately and forgotten.
@MainActor
final class TipJar: ObservableObject {

    /// Must match the product IDs created in App Store Connect exactly.
    static let productIDs = [
        "com.openelsewhere.app.tip.small",
        "com.openelsewhere.app.tip.medium",
        "com.openelsewhere.app.tip.large"
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPurchasing = false

    /// Set after a verified purchase so the UI can show a thank-you.
    @Published var didTip = false

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            // Product loading fails offline, and before the products are
            // approved in App Store Connect. The UI simply shows nothing.
            print("OpenElsewhere: failed to load tip products — \(error.localizedDescription)")
        }
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    didTip = true
                case .unverified(_, let error):
                    print("OpenElsewhere: unverified tip transaction — \(error.localizedDescription)")
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            print("OpenElsewhere: tip purchase failed — \(error.localizedDescription)")
        }
    }
}
