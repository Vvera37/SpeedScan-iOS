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
    private func layoutText(from observations: [RecognizedTextObservation]) -> String {
        // ── 噪声过滤：纯装饰性符号整行过滤 ──────────────────────────
        let noiseRegex = try? NSRegularExpression(pattern: #"^[\s\>\>\》\〉\|\-\_\=\.\,\*\~\#\@\!]+$"#)

        struct Block {
            let text: String
            let minX: CGFloat
            let maxX: CGFloat
            let midY: CGFloat  // Vision y 原点在底部，midY 越大越靠上
        }

        // ── 构建文字块 ────────────────────────────────────────────────
        var blocks: [Block] = []
        for obs in observations {
            guard let top = obs.topCandidates(1).first else { continue }
            var str = top.string.trimmingCharacters(in: .whitespaces)
            guard !str.isEmpty else { continue }

            // 噪声行过滤
            if let re = noiseRegex, re.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)) != nil { continue }

            // 行内噪声清理：去除行首行尾的连续 > / 》
            str = str.replacingOccurrences(of: #"^[\>\》\〉]+"#, with: "", options: .regularExpression)
            str = str.replacingOccurrences(of: #"[\>\》\〉]+$"#, with: "", options: .regularExpression)
            str = str.trimmingCharacters(in: .whitespaces)
            guard !str.isEmpty else { continue }

            // iOS 18: boundingBox 是 NormalizedRect，须 .cgRect 才能取 CGRect 属性
            let rect = obs.boundingBox.cgRect
            let midY = rect.minY + rect.height / 2
            blocks.append(Block(text: str, minX: rect.minX, maxX: rect.maxX, midY: midY))
        }

        // ── 行聚合：Vision y 原点在底部，大 → 小 = 从上到下 ─────────
        let sorted = blocks.sorted { $0.midY > $1.midY }
        let yThreshold: CGFloat = 0.01  // 1% 归一化，更严格的行对齐
        var rows: [[Block]] = []
        for block in sorted {
            if let last = rows.indices.last,
               abs(block.midY - rows[last][0].midY) < yThreshold {
                rows[last].append(block)
            } else {
                rows.append([block])
            }
        }

        // ── 计算平均行高（用于段落空行判断）────────────────────────
        // rows 中每行的代表 midY 取第一个 block
        let rowMidYs = rows.map { $0[0].midY }
        var avgLineHeight: CGFloat = 0.04  // 默认值，防止除零
        if rowMidYs.count >= 2 {
            var gaps: [CGFloat] = []
            for i in 1..<rowMidYs.count {
                let gap = rowMidYs[i - 1] - rowMidYs[i]  // 从上到下，前 > 后，gap > 0
                if gap > 0 { gaps.append(gap) }
            }
            if !gaps.isEmpty {
                avgLineHeight = gaps.reduce(0, +) / CGFloat(gaps.count)
            }
        }
        let paragraphBreakThreshold = avgLineHeight * 1.5  // 超过 1.5 倍行高视为段落间距

        // ── 行内重建：按 minX 排序，大间距用 §GAP:0.xx§ 占位符标记 ──
        // 占位符由 UI 层根据实际屏幕宽度渲染为合适数量的点号，避免小屏换行
        let columnGapThreshold: CGFloat = 0.1  // 归一化间距 > 10% 认为是分栏

        var outputLines: [String] = []
        for (rowIdx, row) in rows.enumerated() {
            // 段落空行：与上一行间距 > 1.5 倍行高，插入空行
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
                        // 用占位符记录间距比例，UI 层动态计算点号数
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

    /// 将 layoutText 输出的占位符转换为实际点号，供 UI 层在已知屏幕宽度时调用
    /// - Parameter text: 含 §GAP:x.xxx§ 占位符的原始文本
    /// - Parameter availableWidth: 可用宽度（点，UITextView 的实际宽度）
    /// - Parameter fontSize: 字体大小（等宽字体每字符宽度 ≈ fontSize * 0.6）
    static func renderDots(in text: String, availableWidth: CGFloat, fontSize: CGFloat) -> String {
        let charWidth = fontSize * 0.6  // 等宽字体经验值
        let totalChars = Int(availableWidth / charWidth)

        // 按行处理，每行独立计算点号数
        let lines = text.components(separatedBy: "\n")
        let rendered = lines.map { line -> String in
            guard line.contains("§GAP:") else { return line }

            // 计算该行去掉占位符后的纯文本字符数
            let stripped = line.replacingOccurrences(of: #"§GAP:[0-9.]+§"#, with: "", options: .regularExpression)
            let usedChars = stripped.count
            let remaining = totalChars - usedChars - 2  // 留 2 个空格边距

            // 动态点号数：剩余空间的 80%，最少 3 个，最多 20 个
            let dotCount = min(20, max(3, Int(CGFloat(remaining) * 0.8)))
            let dots = " " + String(repeating: ".", count: dotCount) + " "

            return line.replacingOccurrences(of: #"§GAP:[0-9.]+§"#, with: dots, options: .regularExpression)
        }
        return rendered.joined(separator: "\n")
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
