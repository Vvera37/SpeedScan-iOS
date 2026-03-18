//
// AuthService.swift
// 手机号登录 API 封装（客户端）
//
// ⚠️ API 联调说明：
//   - 目前 baseURL 为占位符，后端接入后替换为真实地址即可
//   - 发送验证码：POST /api/auth/send-code   body: { "phone": "138xxxx" }
//   - 登录：       POST /api/auth/login       body: { "phone": "138xxxx", "code": "123456" }
//                  response: { "token": "xxx", "expires_at": "ISO8601" }
//

import Foundation

struct AuthService {

    // 后端地址（临时切换到 Sealos 原始地址，自定义域名证书修复中）
    // TODO: 证书恢复后改回 https://api.vmingstudio.com
    static let baseURL = "http://rnqvgzqtcjej.sealosbja.site"

    // MARK: - 发送验证码
    static func sendCode(phone: String) async throws {
        let url = URL(string: "\(baseURL)/api/auth/send-code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body = ["phone": phone]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError("发送验证码失败，请稍后重试")
        }
    }

    // MARK: - 登录
    static func login(phone: String, code: String) async throws -> LoginResponse {
        let url = URL(string: "\(baseURL)/api/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body = ["phone": phone, "code": code]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.serverError("登录失败，请检查验证码")
        }

        let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
        return loginResponse
    }
}

// MARK: - 响应模型
struct LoginResponse: Codable {
    let token: String
    let expiresAt: String   // ISO8601

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
    }

    var expiryDate: Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: expiresAt)
    }
}

// MARK: - 错误类型
enum AuthError: LocalizedError {
    case invalidPhone
    case invalidCode
    case serverError(String)
    case networkError

    var errorDescription: String? {
        switch self {
        case .invalidPhone: return "手机号格式不正确"
        case .invalidCode: return "验证码格式错误"
        case .serverError(let msg): return msg
        case .networkError: return "网络连接失败，请检查网络"
        }
    }
}
