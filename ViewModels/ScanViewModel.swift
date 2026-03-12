//
// ScanViewModel.swift
// OCR 核心逻辑 — Vision 框架端侧识别
//

import SwiftUI
import Vision
import NaturalLanguage
import SwiftData

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

        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self else { return }

            if let error = error {
                Task { @MainActor in
                    self.isProcessing = false
                    self.showAlert(title: "识别错误", message: error.localizedDescription)
                }
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                Task { @MainActor in
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

            // 语言检测
            let lang = self.detectLanguage(text)

            Task { @MainActor in
                self.isProcessing = false
                self.scanResult = OCRResult(
                    originalImage: image,
                    recognizedText: text,
                    detectedLanguage: lang,
                    confidence: avgConfidence,
                    timestamp: Date()
                )
            }
        }

        // 配置 OCR 选项
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en", "ja", "ko"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        Task.detached(priority: .userInitiated) {
            do {
                try handler.perform([request])
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.showAlert(title: "识别错误", message: error.localizedDescription)
                }
            }
        }
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
struct OCRResult: Identifiable {
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
