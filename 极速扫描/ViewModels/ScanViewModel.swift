//
// OCR核心逻辑 - Vision框架端侧识别
//

import SwiftUI
import Vision
import NaturalLanguage

class ScanViewModel: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var scanResult: OCRResult?
    @Published var isProcessing = false
    @Published var errorMessage: String?
    
    // MARK: - 执行OCR识别
    func performOCR() {
        guard let image = selectedImage else { return }
        isProcessing = true
        errorMessage = nil
        
        // 压缩图片以提高处理速度
        guard let compressedImage = compressImage(image),
              let cgImage = compressedImage.cgImage else {
            isProcessing = false
            errorMessage = NSLocalizedString("error_image", comment: "")
            return
        }
        
        // Vision OCR请求
        let request = VNRecognizeTextRequest { [weak self] request, error in
            DispatchQueue.main.async {
                self?.isProcessing = false
                
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    self?.errorMessage = NSLocalizedString("error_recognition", comment: "")
                    return
                }
                
                // 提取识别结果
                let recognizedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")
                
                // 检测语言
                let detectedLang = self?.detectLanguage(recognizedText) ?? "zh-Hans"
                
                // 创建结果
                self?.scanResult = OCRResult(
                    originalImage: image,
                    recognizedText: recognizedText,
                    detectedLanguage: detectedLang,
                    timestamp: Date()
                )
            }
        }
        
        // 配置识别选项
        request.recognitionLevel = .accurate  // 高精度模式
        request.usesLanguageCorrection = true  // 启用语言校正
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en", "ja", "ko"]  // 支持语言
        
        // 执行请求
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.errorMessage = error.localizedDescription
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
        let tagger = NLTagger(tagSchemes: [.language])
        tagger.string = text
        if let language = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .language)?.0 {
            return language.rawValue
        }
        return "zh-Hans"
    }
}

// MARK: - OCR结果模型
struct OCRResult {
    let originalImage: UIImage
    let recognizedText: String
    let detectedLanguage: String
    let timestamp: Date
    
    var isChinese: Bool {
        detectedLanguage.hasPrefix("zh")
    }
}
