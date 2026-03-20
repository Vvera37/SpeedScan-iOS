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

        guard !observations.isEmpty else {
            throw OCRError.noTextFound
        }

        // 坐标重构：还原原图排版结构
        let text = layoutText(from: observations)
        let lang = detectLanguage(text)

        let totalConfidence = observations.compactMap { $0.topCandidates(1).first?.confidence }.reduce(0, +)
        let avgConfidence = Double(totalConfidence / Float(observations.count))

        return OCRResult(
            originalImage: image,
            recognizedText: text,
            detectedLanguage: lang,
            confidence: avgConfidence,
            timestamp: Date()
        )
    }

    // MARK: - 版面还原算法（行对齐 + 列分栏）
    /// Vision 返回归一化坐标（左下角为原点，y 向上），需翻转 y 轴
    private func layoutText(from observations: [RecognizedTextObservation]) -> String {
        // 噪声符号过滤
        let noisePattern = #"^[》》\>\>\s\|\-\_\=\.\,]+$"#
        let noiseRegex = try? NSRegularExpression(pattern: noisePattern)

        struct Block {
            let text: String
            let minX: CGFloat
            let midY: CGFloat  // 翻转后的 y（越大越靠上）
        }

        var blocks: [Block] = []
        for obs in observations {
            guard let top = obs.topCandidates(1).first else { continue }
            let str = top.string.trimmingCharacters(in: .whitespaces)
            guard !str.isEmpty else { continue }

            // 过滤纯噪声行
            if let regex = noiseRegex {
                let range = NSRange(str.startIndex..., in: str)
                if regex.firstMatch(in: str, range: range) != nil { continue }
            }

            let box = obs.boundingBox  // CGRect，归一化，左下角为原点，y 轴向上
            // 翻转 y 轴：midY 越大越靠上 → 翻转后从小到大 = 从上到下
            let flippedMidY = 1.0 - (box.minY + box.height / 2)
            blocks.append(Block(text: str, minX: box.minX, midY: flippedMidY))
        }

        // 翻转后 midY 小 = 靠上，从小到大排 = 从上到下
        let sorted = blocks.sorted { $0.midY < $1.midY }

        // 行聚合：y 轴差值在阈值内归为同一行
        let yThreshold: CGFloat = 0.02  // 归一化坐标 2%，容错同行对齐
        var rows: [[Block]] = []
        for block in sorted {
            if let lastRowIdx = rows.indices.last,
               abs(block.midY - rows[lastRowIdx][0].midY) < yThreshold {
                rows[lastRowIdx].append(block)
            } else {
                rows.append([block])
            }
        }

        // 每行内按 x 排序（从左到右），决定是否需要列分栏
        let lines: [String] = rows.map { row in
            let rowSorted = row.sorted { $0.minX < $1.minX }

            // 判断是否多列（列间距 > 0.25 认为是分栏）
            if rowSorted.count >= 2 {
                var mergedTokens: [String] = []
                var prevMaxX: CGFloat = 0
                for (i, block) in rowSorted.enumerated() {
                    if i == 0 {
                        mergedTokens.append(block.text)
                        prevMaxX = block.minX + 0.3  // 估算宽度
                    } else {
                        let gap = block.minX - prevMaxX
                        if gap > 0.2 {
                            // 明显列间距，用制表符分隔
                            mergedTokens.append("\t\(block.text)")
                        } else {
                            mergedTokens.append(" \(block.text)")
                        }
                        prevMaxX = block.minX + 0.3
                    }
                }
                return mergedTokens.joined()
            } else {
                return rowSorted.map(\.text).joined(separator: " ")
            }
        }

        return lines.joined(separator: "\n")
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
                allText.append(pageText)

                let lines = observations.compactMap { $0.topCandidates(1).first }
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
