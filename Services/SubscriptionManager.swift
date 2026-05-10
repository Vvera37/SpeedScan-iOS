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
    @Published var expiryDate: Date? = nil       // 当前会员最新有效期
    @Published var currentPlanName: String = ""  // "月度会员" / "年度会员"
    @Published var products: [Product] = []
    @Published var isLoading: Bool = false
    @Published var purchaseError: String?
    @Published var showPurchaseSuccess: Bool = false  // 购买成功弹窗触发

    private var updatesTask: Task<Void, Never>?

    // MARK: - 本地永久会员白名单（兜底，无需发版可改数据库）
    private static let permanentVIPPhones: Set<String> = [
        "18565333976",
        "18221177805"
    ]

    init() {
        // 永久会员：从 UserDefaults 立即恢复（不等网络）
        if UserDefaults.standard.bool(forKey: "is_permanent_vip") {
            isPremium = true
            currentPlanName = "永久会员"
        }
        // 本地白名单兜底（服务器未部署时也能用）
        let phone = KeychainService.load(key: "user_phone") ?? ""
        if Self.permanentVIPPhones.contains(phone) {
            isPremium = true
            currentPlanName = "永久会员"
        }
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

    // MARK: - 检查当前订阅状态（取所有 entitlements 里最新有效期）
    func checkSubscriptionStatus() async {
        var latestExpiry: Date? = nil
        var latestPlanName: String = ""
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.monthlyProductID ||
               transaction.productID == Self.yearlyProductID {
                isPremium = true
                if let expiry = transaction.expirationDate {
                    if latestExpiry == nil || expiry > latestExpiry! {
                        latestExpiry = expiry
                        latestPlanName = transaction.productID == Self.yearlyProductID ? "年度会员" : "月度会员"
                    }
                }
            }
        }
        expiryDate = latestExpiry
        currentPlanName = latestPlanName
        if latestExpiry == nil { isPremium = false }

        // 永久会员标记覆盖 StoreKit 结果
        if UserDefaults.standard.bool(forKey: "is_permanent_vip") {
            isPremium = true
            currentPlanName = "永久会员"
            expiryDate = nil
        }
        // 本地白名单兜底
        let phone = KeychainService.load(key: "user_phone") ?? ""
        if Self.permanentVIPPhones.contains(phone) {
            isPremium = true
            currentPlanName = "永久会员"
            expiryDate = nil
        }
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

                await transaction.finish()

                // 直接用本次 transaction 的权威数据更新 UI
                isPremium = true
                currentPlanName = transaction.productID == Self.yearlyProductID ? "年度会员" : "月度会员"
                if let expiry = transaction.expirationDate {
                    expiryDate = expiry
                }
                showPurchaseSuccess = true

                // 后端验证（异步，不阻塞 UI）：写入 vip_users，支持跨设备查询
                Task {
                    await verifyWithBackend(
                        transactionId: String(transaction.id),
                        productId: transaction.productID
                    )
                }

                // 延迟2秒后再跑一次完整校验
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    Task { await self.checkSubscriptionStatus() }
                }

            case .userCancelled:
                break

            case .pending:
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

    // MARK: - 后端验证（写入 vip_users，支持手机号跨设备同步）
    func verifyWithBackend(transactionId: String, productId: String) async {
        guard let url = URL(string: "https://vsrvioxdwtde.cloud.sealos.io/api/subscription/verify") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Device UUID（Keychain 存储，持久唯一）
        if let uuid = KeychainService.load(key: "device_uuid") {
            request.setValue(uuid, forHTTPHeaderField: "X-Device-UUID")
        }

        // 如果已登录，带上 token（后端会优先用手机号）
        if let token = KeychainService.load(key: "auth_token"), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body = ["transactionId": transactionId, "productId": productId]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResp = response as? HTTPURLResponse {
                print("[SubscriptionManager] 后端验证结果: \(httpResp.statusCode)")
            }
        } catch {
            // 静默失败：本地 StoreKit 已是主要验证来源，后端是增强同步
            print("[SubscriptionManager] 后端验证请求失败: \(error.localizedDescription)")
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
                await transaction.finish()
                if transaction.productID == Self.monthlyProductID ||
                   transaction.productID == Self.yearlyProductID {
                    await checkSubscriptionStatus()
                }
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
