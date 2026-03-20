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

        let observations = try await request.perform(on: cgImage, orientation: .up)
        guard !observations.isEmpty else { throw OCRError.noTextFound }

        let text = layoutText(from: observations)
        let lang = detectLanguage(text)
        let totalConfidence = observations.compactMap { $0.topCandidates(1).first?.confidence }.reduce(0, +)
        let avgConfidence = Double(totalConfidence / Float(observations.count))

        return OCRResult(
            originalImage: image,
            recognizedText: text,
            detectedLanguage: lang,
            confidence: avgConfidence,
            timestamp: Date(),
            pages: []   // 单图，pages 为空
        )
    }

    // MARK: - 版面还原算法（行对齐 + 列分栏）
    private func layoutText(from observations: [RecognizedTextObservation]) -> String {
        let noiseRegex = try? NSRegularExpression(pattern: #"^[\s\>\>\》\〉\|\-\_\=\.\,\*\~\#\@\!]+$"#)

        struct Block {
            let text: String
            let minX: CGFloat
            let maxX: CGFloat
            let midY: CGFloat
        }

        var blocks: [Block] = []
        for obs in observations {
            guard let top = obs.topCandidates(1).first else { continue }
            var str = top.string.trimmingCharacters(in: .whitespaces)
            guard !str.isEmpty else { continue }

            if let re = noiseRegex,
               re.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)) != nil { continue }

            str = str.replacingOccurrences(of: #"^[\>\》\〉]+"#, with: "", options: .regularExpression)
            str = str.replacingOccurrences(of: #"[\>\》\〉]+$"#, with: "", options: .regularExpression)
            str = str.trimmingCharacters(in: .whitespaces)
            guard !str.isEmpty else { continue }

            let rect = obs.boundingBox.cgRect
            let midY = rect.minY + rect.height / 2
            blocks.append(Block(text: str, minX: rect.minX, maxX: rect.maxX, midY: midY))
        }

        let sorted = blocks.sorted { $0.midY > $1.midY }
        let yThreshold: CGFloat = 0.01
        var rows: [[Block]] = []
        for block in sorted {
            if let last = rows.indices.last,
               abs(block.midY - rows[last][0].midY) < yThreshold {
                rows[last].append(block)
            } else {
                rows.append([block])
            }
        }

        let rowMidYs = rows.map { $0[0].midY }
        var avgLineHeight: CGFloat = 0.04
        if rowMidYs.count >= 2 {
            var gaps: [CGFloat] = []
            for i in 1..<rowMidYs.count {
                let gap = rowMidYs[i - 1] - rowMidYs[i]
                if gap > 0 { gaps.append(gap) }
            }
            if !gaps.isEmpty { avgLineHeight = gaps.reduce(0, +) / CGFloat(gaps.count) }
        }
        let paragraphBreakThreshold = avgLineHeight * 1.5
        let columnGapThreshold: CGFloat = 0.1

        var outputLines: [String] = []
        for (rowIdx, row) in rows.enumerated() {
            if rowIdx > 0 {
                let prevMidY = rows[rowIdx - 1][0].midY
                let currMidY = row[0].midY
                if prevMidY - currMidY > paragraphBreakThreshold {
                    outputLines.append("")
                }
            }

            let rowSorted = row.sorted { $0.minX < $1.minX }
            var result = ""
            var prevMaxX: CGFloat = 0

            for (i, block) in rowSorted.enumerated() {
                if i == 0 {
                    result += block.text
                } else {
                    let gap = block.minX - prevMaxX
                    if gap > columnGapThreshold {
                        let gapStr = String(format: "%.3f", gap)
                        result += "§GAP:\(gapStr)§\(block.text)"
                    } else {
                        result += " \(block.text)"
                    }
                }
                prevMaxX = block.maxX
            }
            outputLines.append(result)
        }

        return outputLines.joined(separator: "\n")
    }

    /// 占位符 → 固定 5 个点号，任何屏幕不换行
    static func renderDots(in text: String, availableWidth: CGFloat = 0, fontSize: CGFloat = 14) -> String {
        text.replacingOccurrences(of: #"§GAP:[0-9.]+§"#, with: " ..... ", options: .regularExpression)
    }

    // MARK: - PDF 处理（多页分片，LazyVStack 渲染）
    func processPDF(url: URL, onComplete: (() -> Void)? = nil) {
        guard let pdf = PDFDocument(url: url) else {
            showAlert(title: "打开失败", message: "无法读取该 PDF 文件，请确认文件完整")
            return
        }
        isProcessing = true
        scanResult = nil

        Task {
            var pages: [ScanPage] = []
            var totalConfidence: Double = 0
            var observationCount = 0
            var firstImage: UIImage?

            for i in 0..<min(pdf.pageCount, 20) {
                guard let page = pdf.page(at: i) else { continue }

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
                let pageText = layoutText(from: observations)
                pages.append(ScanPage(id: i + 1, content: pageText))

                let lines = observations.compactMap { $0.topCandidates(1).first }
                totalConfidence += lines.reduce(0.0) { $0 + Double($1.confidence) }
                observationCount += lines.count
            }

            let fullText = pages.map(\.content).joined(separator: "\n\n")
            let avgConfidence = observationCount > 0 ? totalConfidence / Double(observationCount) : 0
            let lang = detectLanguage(fullText)

            self.isProcessing = false
            self.scanResult = OCRResult(
                originalImage: firstImage ?? UIImage(),
                recognizedText: fullText.isEmpty ? "未能从 PDF 中提取到文字" : fullText,
                detectedLanguage: lang,
                confidence: avgConfidence,
                timestamp: Date(),
                pages: pages
            )
            onComplete?()
        }
    }

    // MARK: - 图片方向归一化
    private func normalizeOrientation(_ image: UIImage, maxDimension: CGFloat = 2048) -> UIImage? {
        let size = image.size
        var targetSize = size
        if size.width > maxDimension || size.height > maxDimension {
            let scale = maxDimension / max(size.width, size.height)
            targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        }
        return UIGraphicsImageRenderer(size: targetSize).image { _ in
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
            DocxExporter.export(text: result.recognizedText, isPremium: isPremium, fileName: "ScanResult")
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

// MARK: - PDF 分片数据模型
struct ScanPage: Identifiable {
    let id: Int        // 页码，从 1 开始
    let content: String  // 含 §GAP§ 占位符的原始文本
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
    let pages: [ScanPage]   // PDF 多页分片；单图时为空

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
