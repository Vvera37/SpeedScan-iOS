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

    // MARK: - 图片数组 → PDF（iLovePDF 只支持 imagepdf，PPT 功能后续处理）
    static func imagesToPdf(images: [UIImage]) async throws -> URL {
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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 150

        let body = ["images": base64Images]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConvertError.serverError("响应异常")
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
    static func pdfToWord(pdfUrl: URL) async throws -> URL {
        guard let pdfData = try? Data(contentsOf: pdfUrl) else {
            throw ConvertError.fileReadError
        }
        let base64Pdf = pdfData.base64EncodedString()

        let url = URL(string: "\(baseURL)/api/convert/pdf-to-word")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body = ["pdf": base64Pdf]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConvertError.serverError("响应异常")
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
