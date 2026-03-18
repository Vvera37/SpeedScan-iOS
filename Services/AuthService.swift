//
// AuthService.swift
// 手机号登录 API 封装（客户端）
//

import Foundation

struct AuthService {

    // 后端地址
    static let baseURL = "https://api.vmingstudio.com"

    // MARK: - 发送验证码
    static func sendCode(phone: String) async throws {
        let url = URL(string: "\(baseURL)/api/auth/send-code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body = ["phone": phone]
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.serverError("服务器响应异常，请稍后再试")
            }
            // 解析服务端返回的错误信息
            if !(200...299).contains(httpResponse.statusCode) {
                let msg = parseServerError(data: data, statusCode: httpResponse.statusCode, context: .sendCode)
                throw AuthError.serverError(msg)
            }
        } catch let error as AuthError {
            throw error
        } catch let urlError as URLError {
            throw AuthError.networkError(urlError)
        } catch {
            throw AuthError.serverError("验证码发送失败，请检查网络后重试")
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

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.serverError("服务器响应异常，请稍后再试")
            }
            if !(200...299).contains(httpResponse.statusCode) {
                let msg = parseServerError(data: data, statusCode: httpResponse.statusCode, context: .login)
                throw AuthError.serverError(msg)
            }
            return try JSONDecoder().decode(LoginResponse.self, from: data)
        } catch let error as AuthError {
            throw error
        } catch let urlError as URLError {
            throw AuthError.networkError(urlError)
        } catch {
            throw AuthError.serverError("登录失败，请稍后重试")
        }
    }

    // MARK: - 解析服务端错误（映射为用户友好文案）
    private enum RequestContext { case sendCode, login }

    private static func parseServerError(data: Data, statusCode: Int, context: RequestContext) -> String {
        // 尝试读取服务端 error 字段
        if let json = try? JSONDecoder().decode([String: String].self, from: data),
           let serverMsg = json["error"] {
            // 将后端错误码映射为用户友好文案
            switch serverMsg {
            case "手机号格式不正确":
                return "手机号格式有误，请重新输入"
            case "短信发送失败，请稍后重试":
                return "短信发送遇到问题，请稍等片刻再试"
            case "验证码不存在，请重新获取":
                return "验证码已失效，请重新发送"
            case "验证码已过期，请重新获取":
                return "验证码已过期，请重新获取"
            case "验证码错误，请重新输入":
                return "验证码不正确，请检查后重试"
            case "验证次数过多，请重新获取验证码":
                return "输入错误次数过多，请重新获取验证码"
            default:
                break
            }
        }

        // 按 HTTP 状态码兜底
        switch statusCode {
        case 400: return context == .sendCode ? "手机号格式有误，请重新输入" : "输入信息有误，请检查后重试"
        case 401: return "验证码不正确或已过期，请重新获取"
        case 429: return "操作太频繁了，请稍等一分钟再试"
        case 500, 502, 503: return "服务暂时繁忙，请稍后再试"
        default: return "遇到了一点问题（\(statusCode)），请稍后再试"
        }
    }
}

// MARK: - 响应模型
struct LoginResponse: Codable {
    let token: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
    }

    var expiryDate: Date? {
        ISO8601DateFormatter().date(from: expiresAt)
    }
}

// MARK: - 错误类型
enum AuthError: LocalizedError {
    case invalidPhone
    case invalidCode
    case serverError(String)
    case networkError(URLError)

    var errorDescription: String? {
        switch self {
        case .invalidPhone:
            return "手机号格式有误，请重新输入"
        case .invalidCode:
            return "请输入 6 位数字验证码"
        case .serverError(let msg):
            return msg
        case .networkError(let urlError):
            switch urlError.code {
            case .timedOut:
                return "连接超时，请检查网络后重试"
            case .notConnectedToInternet:
                return "没有网络连接，请检查 Wi-Fi 或流量"
            case .secureConnectionFailed, .serverCertificateUntrusted:
                return "安全连接失败，请检查网络环境后重试"
            case .cannotFindHost, .cannotConnectToHost:
                return "无法连接服务器，请稍后再试"
            default:
                return "网络异常，请检查网络后重试"
            }
        }
    }
}
