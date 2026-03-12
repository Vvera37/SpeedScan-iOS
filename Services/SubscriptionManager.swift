//
// SubscriptionManager.swift
// StoreKit 2 订阅管理
//
// ⚠️ 测试说明：
//   - StoreKit 2 需要在真机或 Xcode StoreKit Configuration 文件下测试
//   - 模拟器不支持真实购买，需在 Xcode -> Product -> Scheme -> Edit Scheme
//     -> Run -> StoreKit Configuration 中添加 .storekit 配置文件
//   - Product IDs 需在 App Store Connect 中预先创建
//

import Foundation
import StoreKit

@MainActor
class SubscriptionManager: ObservableObject {

    // MARK: - Product IDs
    static let monthlyProductID = "com.saomiaoji.app.monthly"   // ¥2/月
    static let yearlyProductID  = "com.saomiaoji.app.yearly"    // ¥12/年

    // MARK: - Published 状态
    @Published var isPremium: Bool = false
    @Published var products: [Product] = []
    @Published var isLoading: Bool = false
    @Published var purchaseError: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        // 启动时检查订阅状态
        Task {
            await loadProducts()
            await checkSubscriptionStatus()
        }
        // 监听交易更新
        updatesTask = listenForTransactions()
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - 加载产品列表
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let productIDs: Set<String> = [
                Self.monthlyProductID,
                Self.yearlyProductID
            ]
            // ⚠️ 真实设备+有效 App Store Connect 配置才会返回产品
            products = try await Product.products(for: productIDs)
                .sorted { p1, p2 in
                    // 月度排前面
                    p1.id == Self.monthlyProductID
                }
        } catch {
            print("[SubscriptionManager] 加载产品失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 检查当前订阅状态
    func checkSubscriptionStatus() async {
        // 遍历当前有效的权益
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.monthlyProductID ||
               transaction.productID == Self.yearlyProductID {
                isPremium = true
                return
            }
        }
        isPremium = false
    }

    // MARK: - 购买订阅
    func purchase(product: Product) async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseError = "购买验证失败，请联系客服"
                    return
                }
                isPremium = true
                await transaction.finish()

            case .userCancelled:
                break // 用户取消，静默处理

            case .pending:
                // 等待家长审批等异步状态
                purchaseError = "购买处于等待状态，请稍后检查"

            @unknown default:
                break
            }
        } catch StoreKitError.userCancelled {
            // 静默处理
        } catch {
            purchaseError = "购买失败：\(error.localizedDescription)"
            print("[SubscriptionManager] 购买错误: \(error)")
        }
    }

    // MARK: - 恢复购买
    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // StoreKit 2 会自动同步，手动触发一次检查
            try await AppStore.sync()
            await checkSubscriptionStatus()
        } catch {
            purchaseError = "恢复失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 监听交易更新（后台续费、退款等）
    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await MainActor.run {
                    if transaction.productID == Self.monthlyProductID ||
                       transaction.productID == Self.yearlyProductID {
                        self.isPremium = true
                    }
                }
                await transaction.finish()
            }
        }
    }

    // MARK: - 便捷属性：月度/年度产品
    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductID }
    }
    var yearlyProduct: Product? {
        products.first { $0.id == Self.yearlyProductID }
    }
}
