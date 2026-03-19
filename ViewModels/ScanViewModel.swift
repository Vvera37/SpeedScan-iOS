//
// ScanViewModel.swift
// OCR 核心逻辑 — Vision 框架端侧识别
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

        guard let compressedImage = compressImage(image),
              let cgImage = compressedImage.cgImage else {
            isProcessing = false
            showAlert(title: "错误", message: "图片处理失败，请重试")
            return
        }

        // iOS 17+ 推荐写法：使用 revision3，避免过时 API 警告
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // zh-Hant 放首位：繁体优先匹配，兼顾简体/英文/日文/韩文
        request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US", "ja-JP", "ko-KR"]
        request.automaticallyDetectsLanguage = true
        // iOS 16+ 推荐：明确指定 revision，消除 deprecation 警告
        request.revision = VNRecognizeTextRequestRevision3

        let handler = VNImageRequestHandler(cgImage: cgImage)
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try handler.perform([request])

                guard let observations = request.results else {
                    await MainActor.run {
                        self.isProcessing = false
                        self.showAlert(title: "识别失败", message: "未能从图片中提取到文字，请确认图片清晰")
                    }
                    return
                }

                // 提取文字 + 计算置信度均值
                var totalConfidence: Float = 0
                var lines: [String] = []
                for obs in observations {
                    if let top = obs.topCandidates(1).first {
                        lines.append(top.string)
                        totalConfidence += top.confidence
                    }
                }
                let text = lines.joined(separator: "\n")
                let avgConfidence = observations.isEmpty ? 0 : Double(totalConfidence / Float(observations.count))
                let lang = self.detectLanguage(text)

                await MainActor.run {
                    self.isProcessing = false
                    self.scanResult = OCRResult(
                        originalImage: image,
                        recognizedText: text,
                        detectedLanguage: lang,
                        confidence: avgConfidence,
                        timestamp: Date()
                    )
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.showAlert(title: "识别错误", message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - PDF 处理（多页合并 OCR）
    func processPDF(url: URL, onComplete: (() -> Void)? = nil) {
        guard let pdf = PDFDocument(url: url) else {
            showAlert(title: "打开失败", message: "无法读取该 PDF 文件，请确认文件完整")
            return
        }
        isProcessing = true
        scanResult = nil

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            var allText: [String] = []
            var totalConfidence: Double = 0
            var observationCount = 0
            var firstImage: UIImage?

            for i in 0..<min(pdf.pageCount, 20) {
                guard let page = pdf.page(at: i) else { continue }

                // PDF 页 → UIImage
                let pageRect = page.bounds(for: .mediaBox)
                let scale: CGFloat = 2.0  // 2x 清晰度
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

                // OCR 识别（iOS 17+ 现代写法，消除 deprecation 警告）
                guard let cgImage = pageImage.cgImage else { continue }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US", "ja-JP", "ko-KR"]
                request.automaticallyDetectsLanguage = true
                request.revision = VNRecognizeTextRequestRevision3

                try? VNImageRequestHandler(cgImage: cgImage).perform([request])

                let observations = request.results ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first }
                allText.append(lines.map(\.string).joined(separator: "\n"))
                totalConfidence += lines.reduce(0.0) { $0 + Double($1.confidence) }
                observationCount += lines.count
            }

            let fullText = allText.joined(separator: "\n\n")
            let avgConfidence = observationCount > 0 ? totalConfidence / Double(observationCount) : 0
            let lang = await self.detectLanguageAsync(fullText)
            let thumbnail = firstImage ?? UIImage()

            await MainActor.run {
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

    private func detectLanguageAsync(_ text: String) async -> String {
        detectLanguage(text)
    }

    // MARK: - 图片压缩
    private func compressImage(_ image: UIImage, maxDimension: CGFloat = 2048) -> UIImage? {
        let size = image.size
        var newSize = size
        if size.width > maxDimension || size.height > maxDimension {
            let scale = maxDimension / max(size.width, size.height)
            newSize = CGSize(width: size.width * scale, height: size.height * scale)
        }
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let compressed = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return compressed
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
    /// 生成 .docx 文件，返回文件路径（在后台线程执行）
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

// MARK: - OCR 结果模型
struct OCRResult: Identifiable, Equatable {
    static func == (lhs: OCRResult, rhs: OCRResult) -> Bool {
        lhs.id == rhs.id
    }
    let id = UUID()
    let originalImage: UIImage
    let recognizedText: String
    let detectedLanguage: String
    let confidence: Double       // 0.0 ~ 1.0
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
