//
//  OCRService.swift
//  SpeedScan
//
//  调用后端 Claude Vision 接口，识别图片中的文字（含手写体）
//  POST /api/ocr/handwriting
//

import UIKit
import Foundation

enum OCRService {
    private static let baseURL = AuthService.baseURL

    /// 识别图片中的文字（印刷体 + 手写体）
    static func recognizeHandwriting(image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw OCRServiceError.imageConvertFailed
        }
        let base64 = data.base64EncodedString()

        let url = URL(string: "\(baseURL)/api/ocr/handwriting")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        request.httpBody = try JSONSerialization.data(withJSONObject: ["image": base64])

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: responseData))?["error"] ?? "识别失败"
            throw OCRServiceError.serverError(msg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let text = json["text"] as? String else {
            throw OCRServiceError.parseError
        }
        return text
    }
}

enum OCRServiceError: LocalizedError {
    case imageConvertFailed
    case serverError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .imageConvertFailed: return "图片处理失败，请重试"
        case .serverError(let msg): return msg
        case .parseError: return "返回数据解析失败"
        }
    }
}
