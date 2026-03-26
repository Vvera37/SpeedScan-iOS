//
//  UsageService.swift
//  SpeedScan
//
//  使用量管理：
//  - 本地生成/存储 UUID（未登录时的设备标识）
//  - 登录时在请求头传 X-Device-UUID，后端自动合并
//  - 提供 checkQuota / recordUsage 方法（直接调后端）
//

import Foundation
import UIKit

// MARK: - Feature 枚举
enum UsageFeature: String {
    case ocr        = "ocr"
    case imagesPdf  = "images_pdf"
    case pdfWord    = "pdf_word"

    var displayName: String {
        switch self {
        case .ocr:       return "AI 识别"
        case .imagesPdf: return "图片转 PDF"
        case .pdfWord:   return "PDF 转 Word"
        }
    }

    var freeLimit: Int {
        switch self {
        case .ocr:       return 20
        case .imagesPdf: return 5
        case .pdfWord:   return 5
        }
    }
}

// MARK: - 超限错误
struct QuotaExceededError: LocalizedError {
    let feature: UsageFeature
    let used: Int
    let limit: Int

    var errorDescription: String? {
        return "已超过免费次数，AI识别费用较高，请购买VIP后继续使用"
    }
}

// MARK: - UsageService
enum UsageService {

    private static let baseURL = AuthService.baseURL

    /// UUID Keychain 键名
    private static let uuidKey = "device_uuid"

    // MARK: - 获取/生成设备 UUID（持久化到 Keychain）
    static var deviceUUID: String {
        if let existing = KeychainService.load(key: uuidKey), !existing.isEmpty {
            return existing
        }
        let newUUID = UUID().uuidString
        KeychainService.save(key: uuidKey, value: newUUID)
        return newUUID
    }

    // MARK: - 构建请求头（自动带 UUID 和 Token）
    static func buildHeaders(token: String?) -> [String: String] {
        var headers: [String: String] = [
            "Content-Type":   "application/json",
            "X-Device-UUID":  deviceUUID,
        ]
        if let token = token, !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }
        return headers
    }

    // MARK: - 检查使用量（调后端 /api/usage/check）
    // 返回 true 表示允许，返回 false 抛 QuotaExceededError
    static func checkQuota(feature: UsageFeature, token: String?) async throws {
        let url = URL(string: "\(baseURL)/api/usage/check")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        for (k, v) in buildHeaders(token: token) { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["feature": feature.rawValue])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }

        if http.statusCode == 402 {
            // 超限
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let used  = json["used"]  as? Int ?? feature.freeLimit
            let limit = json["limit"] as? Int ?? feature.freeLimit
            throw QuotaExceededError(feature: feature, used: used, limit: limit)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let allowed = json["allowed"] as? Bool, !allowed {
            let used  = json["used"]  as? Int ?? feature.freeLimit
            let limit = json["limit"] as? Int ?? feature.freeLimit
            throw QuotaExceededError(feature: feature, used: used, limit: limit)
        }
    }

    // MARK: - 记录使用（操作成功后调用，调后端 /api/usage/record）
    static func recordUsage(feature: UsageFeature, token: String?) async {
        guard let url = URL(string: "\(baseURL)/api/usage/record") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        for (k, v) in buildHeaders(token: token) { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["feature": feature.rawValue])

        // 静默发送，不阻断主流程
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - 查询使用状态（供 ProfileView 展示）
    static func fetchStatus(token: String?) async throws -> UsageStatus {
        let url = URL(string: "\(baseURL)/api/usage/status")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        for (k, v) in buildHeaders(token: token) { request.setValue(v, forHTTPHeaderField: k) }

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(UsageStatus.self, from: data)
    }
}

// MARK: - 使用状态模型（/api/usage/status 响应）
struct UsageStatus: Codable {
    let userId: String
    let type: String
    let vip: Bool
    let status: [String: FeatureStatus]

    struct FeatureStatus: Codable {
        let used: Int
        let limit: Int?
        let remaining: Int?
        let allowed: Bool
    }
}
