//
// ScanViewModel.swift
// OCR 核心逻辑 — iOS 18 Vision 框架（Swift 原生 API）
//

import SwiftUI
import Vision      // iOS 18 新 API：RecognizeTextRequest，无 VN 前缀
import NaturalLanguage
import SwiftData
import PDFKit

@MainActor
class ScanViewModel: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var scanResult: OCRResult?
    @Published var isProcessing = false
    @Published var alertItem: AlertItem?

    // MARK: - 执行 OCR（iOS 18 Swift 原生 Vision API）
    func performOCR() {
        guard let image = selectedImage else { return }
        isProcessing = true
        scanResult = nil

        Task {
            do {
                let result = try await recognizeText(from: image, originalImage: image)
                self.scanResult = result
                self.isProcessing = false
            } catch {
                self.isProcessing = false
                self.showAlert(title: "识别错误", message: error.localizedDescription)
            }
        }
    }

    // MARK: - 核心识别函数（iOS 18 新 API）
    /// iOS 18 RecognizeTextRequest：
    /// - 自动处理图片方向（无需手动纠偏 EXIF）
    /// - async/await 原生支持
    /// - 强类型结果，无需强转
    private func recognizeText(from image: UIImage, originalImage: UIImage) async throws -> OCRResult {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // zh-Hant 优先：繁体证件（香港签证等）识别准确
        request.recognitionLanguages = [
            Locale.Language(identifier: "zh-Hant"),
            Locale.Language(identifier: "zh-Hans"),
            Locale.Language(identifier: "en-US"),
            Locale.Language(identifier: "ja-JP"),
            Locale.Language(identifier: "ko-KR")
        ]
        request.automaticallyDetectsLanguage = true

        // perform(on: UIImage) 自动处理方向，无需 compressImage / EXIF 纠偏
        let observations = try await request.perform(on: image)

        guard !observations.isEmpty else {
            throw OCRError.noTextFound
        }

        var totalConfidence: Float = 0
        var lines: [String] = []
        for obs in observations {
            if let top = obs.topCandidates(1).first {
                lines.append(top.string)
                totalConfidence += top.confidence
            }
        }
        let text = lines.joined(separator: "\n")
        let avgConfidence = Double(totalConfidence / Float(observations.count))
        let lang = detectLanguage(text)

        return OCRResult(
            originalImage: originalImage,
            recognizedText: text,
            detectedLanguage: lang,
            confidence: avgConfidence,
            timestamp: Date()
        )
    }

    // MARK: - PDF 处理（多页合并 OCR）
    func processPDF(url: URL, onComplete: (() -> Void)? = nil) {
        guard let pdf = PDFDocument(url: url) else {
            showAlert(title: "打开失败", message: "无法读取该 PDF 文件，请确认文件完整")
            return
        }
        isProcessing = true
        scanResult = nil

        Task {
            do {
                var allText: [String] = []
                var totalConfidence: Double = 0
                var observationCount = 0
                var firstImage: UIImage?

                for i in 0..<min(pdf.pageCount, 20) {
                    guard let page = pdf.page(at: i) else { continue }

                    // PDF 页 → UIImage（UIGraphicsImageRenderer 输出天然 .up 方向）
                    let pageRect = page.bounds(for: .mediaBox)
                    let scale: CGFloat = 2.0
                    let renderer = UIGraphicsImageRenderer(size: CGSize(
                        width: pageRect.width * scale,
                        height: pageRect.height * scale
                    ))
                    let pageImage = renderer.image { ctx in
                        ctx.cgContext.scaleBy(x: scale, y: scale)
                        UIColor.white.setFill()
                        ctx.fill(CGRect(origin: .zero, size: pageRect.size))
                        page.draw(with: .mediaBox, to: ctx.cgContext)
                    }
                    if firstImage == nil { firstImage = pageImage }

                    // iOS 18 新 API 识别
                    var request = RecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    request.recognitionLanguages = [
                        Locale.Language(identifier: "zh-Hant"),
                        Locale.Language(identifier: "zh-Hans"),
                        Locale.Language(identifier: "en-US"),
                        Locale.Language(identifier: "ja-JP"),
                        Locale.Language(identifier: "ko-KR")
                    ]
                    request.automaticallyDetectsLanguage = true

                    let observations = (try? await request.perform(on: pageImage)) ?? []
                    let lines = observations.compactMap { $0.topCandidates(1).first }
                    allText.append(lines.map(\.string).joined(separator: "\n"))
                    totalConfidence += lines.reduce(0.0) { $0 + Double($1.confidence) }
                    observationCount += lines.count
                }

                let fullText = allText.joined(separator: "\n\n")
                let avgConfidence = observationCount > 0 ? totalConfidence / Double(observationCount) : 0
                let lang = detectLanguage(fullText)
                let thumbnail = firstImage ?? UIImage()

                self.isProcessing = false
                self.scanResult = OCRResult(
                    originalImage: thumbnail,
                    recognizedText: fullText.isEmpty ? "未能从 PDF 中提取到文字" : fullText,
                    detectedLanguage: lang,
                    confidence: avgConfidence,
                    timestamp: Date()
                )
                onComplete?()
            }
        }
    }

    // MARK: - 语言检测
    private func detectLanguage(_ text: String) -> String {
        guard !text.isEmpty else { return "zh-Hans" }
        let tagger = NLTagger(tagSchemes: [.language])
        tagger.string = text
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .language)
        return tag?.rawValue ?? "zh-Hans"
    }

    // MARK: - 导出 Word
    func exportWord(isPremium: Bool) async -> String? {
        guard let result = scanResult else { return nil }
        return await Task.detached(priority: .userInitiated) {
            DocxExporter.export(
                text: result.recognizedText,
                isPremium: isPremium,
                fileName: "ScanResult"
            )
        }.value
    }

    // MARK: - 保存到历史记录
    func saveToHistory(context: ModelContext, wordFilePath: String) {
        guard let result = scanResult else { return }
        let preview = String(result.recognizedText.prefix(200))
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: wordFilePath)[.size] as? Int64) ?? 0
        let record = ScanRecord(
            wordFilePath: wordFilePath,
            wordFileSize: fileSize,
            textPreview: preview,
            detectedLanguage: result.detectedLanguage
        )
        context.insert(record)
        try? context.save()
    }

    // MARK: - Alert 辅助
    func showAlert(title: String, message: String) {
        alertItem = AlertItem(
            title: Text(title),
            message: Text(message),
            dismissButton: .default(Text("确定"))
        )
    }
}

// MARK: - OCR 错误
enum OCRError: LocalizedError {
    case noTextFound
    var errorDescription: String? {
        switch self {
        case .noTextFound: return "未能从图片中提取到文字，请确认图片清晰"
        }
    }
}

// MARK: - OCR 结果模型
struct OCRResult: Identifiable, Equatable {
    static func == (lhs: OCRResult, rhs: OCRResult) -> Bool { lhs.id == rhs.id }
    let id = UUID()
    let originalImage: UIImage
    let recognizedText: String
    let detectedLanguage: String
    let confidence: Double
    let timestamp: Date

    var isChinese: Bool {
        detectedLanguage.hasPrefix("zh") || detectedLanguage == "zh"
    }
}

// MARK: - Alert Item
struct AlertItem: Identifiable {
    let id = UUID()
    let title: Text
    let message: Text?
    let dismissButton: Alert.Button?
}
