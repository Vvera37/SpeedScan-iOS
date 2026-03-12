//
// 极速扫描 - iOS App
// SwiftUI + Vision OCR + SwiftData + StoreKit 2
//

import SwiftUI
import Vision
import SwiftData

@main
struct SpeedScanApp: App {

    @StateObject private var appState = AppState()
    @StateObject private var subscriptionManager = SubscriptionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(subscriptionManager)
                // 注入 SwiftData 容器
                .modelContainer(for: ScanRecord.self)
        }
    }
}

// MARK: - 应用全局状态（登录 & Session）
@MainActor
class AppState: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var userPhone: String = ""

    // Keychain 键名
    private let tokenKey     = "auth_token"
    private let phoneKey     = "user_phone"
    private let expiryKey    = "session_expiry"

    init() {
        restoreSession()
    }

    // MARK: - 恢复登录态
    func restoreSession() {
        guard let token = KeychainService.load(key: tokenKey),
              !token.isEmpty,
              let expiryString = KeychainService.load(key: expiryKey),
              let expiry = ISO8601DateFormatter().date(from: expiryString),
              expiry > Date() else {
            isLoggedIn = false
            return
        }
        // 有效 token，自动续期 90 天
        userPhone = KeychainService.load(key: phoneKey) ?? ""
        isLoggedIn = true
        renewSession(token: token)
    }

    // MARK: - 登录成功后保存
    func saveSession(token: String, phone: String, expiresAt: Date?) {
        let expiry = expiresAt ?? Calendar.current.date(byAdding: .day, value: 90, to: Date())!
        KeychainService.save(key: tokenKey, value: token)
        KeychainService.save(key: phoneKey, value: phone)
        KeychainService.save(key: expiryKey, value: ISO8601DateFormatter().string(from: expiry))
        userPhone = phone
        isLoggedIn = true
    }

    // MARK: - 续期（延长 90 天）
    private func renewSession(token: String) {
        let newExpiry = Calendar.current.date(byAdding: .day, value: 90, to: Date())!
        KeychainService.save(key: expiryKey, value: ISO8601DateFormatter().string(from: newExpiry))
    }

    // MARK: - 退出登录
    func logout() {
        KeychainService.delete(key: tokenKey)
        KeychainService.delete(key: phoneKey)
        KeychainService.delete(key: expiryKey)
        userPhone = ""
        isLoggedIn = false
    }

    // MARK: - 当前 Token（供接口调用使用）
    var currentToken: String? {
        KeychainService.load(key: tokenKey)
    }
}
