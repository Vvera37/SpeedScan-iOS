//
//  ConvertService.swift
//  SpeedScan
//
//  调用后端 iLovePDF 转换接口
//  POST /api/convert/images-to-pptx  图片数组 → PPTX
//  POST /api/convert/pdf-to-word     PDF → DOCX
//

import UIKit
import Foundation

enum ConvertService {

    private static let baseURL = AuthService.baseURL

    // MARK: - 图片数组 → PDF
    /// token: 已登录时传入，未登录传 nil
    static func imagesToPdf(images: [UIImage], token: String?) async throws -> URL {
        // ── 使用量前置检查 ──
        try await UsageService.checkQuota(feature: .imagesPdf, token: token)

        let base64Images = images.compactMap { img -> String? in
            guard let data = img.jpegData(compressionQuality: 0.85) else { return nil }
            return data.base64EncodedString()
        }
        guard !base64Images.isEmpty else {
            throw ConvertError.noImages
        }

        let url = URL(string: "\(baseURL)/api/convert/images-to-pptx")!  // 路由名保持兼容
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 150
        for (k, v) in UsageService.buildHeaders(token: token) {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let body = ["images": base64Images]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConvertError.serverError("响应异常")
        }

        if httpResponse.statusCode == 402 {
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let used  = json["used"]  as? Int ?? UsageFeature.imagesPdf.freeLimit
            let limit = json["limit"] as? Int ?? UsageFeature.imagesPdf.freeLimit
            throw QuotaExceededError(feature: .imagesPdf, used: used, limit: limit)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "转换失败"
            throw ConvertError.serverError(msg)
        }

        let tmpUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("document_\(Int(Date().timeIntervalSince1970)).pdf")
        try data.write(to: tmpUrl)
        return tmpUrl
    }

    // MARK: - PDF → Word
    /// token: 已登录时传入，未登录传 nil
    static func pdfToWord(pdfUrl: URL, token: String?) async throws -> URL {
        // ── 使用量前置检查 ──
        try await UsageService.checkQuota(feature: .pdfWord, token: token)

        guard let pdfData = try? Data(contentsOf: pdfUrl) else {
            throw ConvertError.fileReadError
        }
        let base64Pdf = pdfData.base64EncodedString()

        let url = URL(string: "\(baseURL)/api/convert/pdf-to-word")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        for (k, v) in UsageService.buildHeaders(token: token) {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let body = ["pdf": base64Pdf]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConvertError.serverError("响应异常")
        }

        if httpResponse.statusCode == 402 {
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let used  = json["used"]  as? Int ?? UsageFeature.pdfWord.freeLimit
            let limit = json["limit"] as? Int ?? UsageFeature.pdfWord.freeLimit
            throw QuotaExceededError(feature: .pdfWord, used: used, limit: limit)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "转换失败"
            throw ConvertError.serverError(msg)
        }

        let tmpUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("document_\(Int(Date().timeIntervalSince1970)).docx")
        try data.write(to: tmpUrl)
        return tmpUrl
    }
}

// MARK: - 错误类型
enum ConvertError: LocalizedError {
    case noImages
    case fileReadError
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .noImages:        return "没有可转换的图片"
        case .fileReadError:   return "PDF 文件读取失败"
        case .serverError(let msg): return msg
        }
    }
}
