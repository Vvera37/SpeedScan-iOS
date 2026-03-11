//
// OCR核心逻辑 - Vision框架端侧识别
//

import SwiftUI
import Vision
import NaturalLanguage
import UniformTypeIdentifiers

class ScanViewModel: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var scanResult: OCRResult?
    @Published var isProcessing = false
    @Published var alertItem: AlertItem?
    
    private var toastMessage: String = ""
    @Published var showToast: Bool = false
    
    // MARK: - 执行OCR识别
    func performOCR() {
        guard let image = selectedImage else { return }
        isProcessing = true
        
        // 压缩图片以提高处理速度
        guard let compressedImage = compressImage(image),
              let cgImage = compressedImage.cgImage else {
            isProcessing = false
            alertItem = AlertItem(
                title: Text("错误"),
                message: Text(NSLocalizedString("error_image", comment: "")),
                dismissButton: .default(Text("确定"))
            )
            return
        }
        
        // Vision OCR请求
        let request = VNRecognizeTextRequest { [weak self] request, error in
            DispatchQueue.main.async {
                self?.isProcessing = false
                
                if let error = error {
                    self?.alertItem = AlertItem(
                        title: Text("识别错误"),
                        message: Text(error.localizedDescription),
                        dismissButton: .default(Text("确定"))
                    )
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    self?.alertItem = AlertItem(
                        title: Text("识别失败"),
                        message: Text(NSLocalizedString("error_recognition", comment: "")),
                        dismissButton: .default(Text("确定"))
                    )
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
                    self.alertItem = AlertItem(
                        title: Text("识别错误"),
                        message: Text(error.localizedDescription),
                        dismissButton: .default(Text("确定"))
                    )
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
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .language)
        if let language = tag {
            return language.rawValue
        }
        return "zh-Hans"
    }
    
    // MARK: - 导出Word文档
    func exportToWord(result: OCRResult, completion: @escaping (Bool, String?) -> Void) {
        // 创建临时目录
        let tempDir = FileManager.default.temporaryDirectory
        
        // 简化的Word文档生成（实际应使用专业库）
        // 这里先创建纯文本文件作为演示
        let txtFileName = "ScanResult_\(Int(Date().timeIntervalSince1970)).txt"
        let txtFileURL = tempDir.appendingPathComponent(txtFileName)
        
        do {
            try result.recognizedText.write(to: txtFileURL, atomically: true, encoding: .utf8)
            completion(true, txtFileURL.path)
        } catch {
            completion(false, nil)
        }
    }
    
    // MARK: - 分享结果
    func shareResult(result: OCRResult) {
        let items: [Any] = [result.recognizedText]
        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // 获取当前窗口场景
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(ac, animated: true)
        }
    }
    
    // MARK: - Toast提示
    func showToast(_ message: String) {
        toastMessage = message
        // 这里使用另一个变量控制toast显示
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.dismissToast()
        }
    }
    
    func dismissToast() {
        // dismiss 逻辑由调用方处理
    }
}

// MARK: - OCR结果模型
struct OCRResult: Identifiable {
    let id = UUID()
    let originalImage: UIImage
    let recognizedText: String
    let detectedLanguage: String
    let timestamp: Date
    
    var isChinese: Bool {
        detectedLanguage.hasPrefix("zh")
    }
}

// MARK: - Alert Item
struct AlertItem: Identifiable {
    let id = UUID()
    let title: Text
    let message: Text?
    let dismissButton: Alert.Button?
}
