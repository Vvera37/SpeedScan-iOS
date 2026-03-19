//
// ScanViewModel.swift
// OCR 核心逻辑 — iOS 18 Vision 框架（Swift 原生 API）
//

import SwiftUI
import Vision
import NaturalLanguage
import SwiftData
import PDFKit

@MainActor
class ScanViewModel: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var scanResult: OCRResult?
    @Published var isProcessing = false
    @Published var alertItem: AlertItem?

    // MARK: - 执行 OCR
    func performOCR() {
        guard let image = selectedImage else { return }
        isProcessing = true
        scanResult = nil

        Task {
            do {
                let result = try await recognizeText(from: image)
                self.scanResult = result
                self.isProcessing = false
            } catch OCRError.noTextFound {
                self.isProcessing = false
                self.showAlert(title: "识别失败", message: "未能从图片中提取到文字，请确认图片清晰")
            } catch {
                self.isProcessing = false
                self.showAlert(title: "识别错误", message: error.localizedDescription)
            }
        }
    }

    // MARK: - 核心识别（iOS 18 Vision API）
    /// perform(on:) 接受 CGImage，不接受 UIImage。
    /// 先用 UIGraphicsImageRenderer 将 EXIF 方向烘焙进像素（输出 orientation=.up），
    /// 再取 cgImage 传入，orientation 参数显式传 .up，双保险。
    private func recognizeText(from image: UIImage) async throws -> OCRResult {
        guard let normalizedImage = normalizeOrientation(image),
              let cgImage = normalizedImage.cgImage else {
            throw OCRError.imagePrepareFailed
        }

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

        // orientation: .up — 与 normalizeOrientation 输出对齐
        let observations = try await request.perform(on: cgImage, orientation: .up)

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
            originalImage: image,
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

                guard let cgImage = pageImage.cgImage else { continue }

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

                let observations = (try? await request.perform(on: cgImage, orientation: .up)) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first }
                allText.append(lines.map(\.string).joined(separator: "\n"))
                totalConfidence += lines.reduce(0.0) { $0 + Double($1.confidence) }
                observationCount += lines.count
            }

            let fullText = allText.joined(separator: "\n\n")
            let avgConfidence = observationCount > 0 ? totalConfidence / Double(observationCount) : 0
            let lang = detectLanguage(fullText)

            self.isProcessing = false
            self.scanResult = OCRResult(
                originalImage: firstImage ?? UIImage(),
                recognizedText: fullText.isEmpty ? "未能从 PDF 中提取到文字" : fullText,
                detectedLanguage: lang,
                confidence: avgConfidence,
                timestamp: Date()
            )
            onComplete?()
        }
    }

    // MARK: - 图片方向归一化
    /// 用 UIGraphicsImageRenderer 重绘，将 EXIF imageOrientation 烘焙进像素，
    /// 输出的 UIImage.imageOrientation == .up，cgImage 可直接传给 Vision。
    /// 同时限制最大尺寸 2048px，控制内存占用。
    private func normalizeOrientation(_ image: UIImage, maxDimension: CGFloat = 2048) -> UIImage? {
        let size = image.size
        var targetSize = size
        if size.width > maxDimension || size.height > maxDimension {
            let scale = maxDimension / max(size.width, size.height)
            targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        }
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
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
    case imagePrepareFailed
    var errorDescription: String? {
        switch self {
        case .noTextFound:        return "未能从图片中提取到文字，请确认图片清晰"
        case .imagePrepareFailed: return "图片处理失败，请重试"
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
