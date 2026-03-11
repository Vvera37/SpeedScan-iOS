//
// 扫描结果展示界面
//

import SwiftUI

struct ScanResultView: View {
    let result: OCRResult
    @ObservedObject var viewModel: ScanViewModel
    @State private var showTranslation = false
    @State private var translatedText: String = ""
    @State private var isTranslating = false
    @State private var showExportSuccess = false
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // 文字面板
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 原文显示
                    Text(result.recognizedText)
                        .font(.body)
                        .lineSpacing(6)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .contextMenu {
                            Button(action: {
                                UIPasteboard.general.string = result.recognizedText
                            }) {
                                Label(NSLocalizedString("copy_full", comment: ""), systemImage: "doc.on.doc")
                            }
                            
                            Button(action: {
                                viewModel.shareResult(result: result)
                            }) {
                                Label(NSLocalizedString("share", comment: ""), systemImage: "square.and.arrow.up")
                            }
                        }
                    
                    // 非中文时显示翻译按钮
                    if !result.isChinese {
                        Button(action: translateText) {
                            HStack {
                                Image(systemName: "translate")
                                Text(NSLocalizedString("btn_translate", comment: ""))
                                if isTranslating {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(12)
                        }
                        .disabled(isTranslating)
                        
                        // 翻译结果
                        if showTranslation && !translatedText.isEmpty {
                            Text(translatedText)
                                .font(.body)
                                .lineSpacing(6)
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }
                    
                    // 水印（非付费用户）
                    if !appState.isPremium {
                        WatermarkView()
                    }
                }
                .padding()
            }
            
            // 底部操作栏
            HStack(spacing: 20) {
                ActionButton(
                    icon: "doc.on.doc",
                    title: NSLocalizedString("copy_full", comment: ""),
                    action: {
                        UIPasteboard.general.string = result.recognizedText
                        viewModel.showToast("已复制到剪贴板")
                    }
                )
                
                ActionButton(
                    icon: "doc.text",
                    title: NSLocalizedString("export_word", comment: ""),
                    action: exportToWord
                )
                
                ActionButton(
                    icon: "square.and.arrow.up",
                    title: NSLocalizedString("share", comment: ""),
                    action: {
                        viewModel.shareResult(result: result)
                    }
                )
            }
            .padding()
            .background(Color(.systemGray6))
        }
        .overlay(
            // 导出成功提示
            VStack {
                if showExportSuccess {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(NSLocalizedString("export_success", comment: ""))
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 5)
                    .padding(.top, 20)
                    Spacer()
                }
            }
        )
    }
    
    // MARK: - 翻译功能
    private func translateText() {
        isTranslating = true
        
        // 使用Apple翻译API或ML Kit
        // 这里先用简化实现
        DispatchQueue.global(qos: .userInitiated).async {
            // 模拟翻译延迟
            Thread.sleep(forTimeInterval: 1.0)
            
            // 实际应调用翻译API
            let translated = "[翻译结果]\n\(result.recognizedText.prefix(100))..."
            
            DispatchQueue.main.async {
                self.translatedText = translated
                self.showTranslation = true
                self.isTranslating = false
            }
        }
    }
    
    // MARK: - 导出Word
    private func exportToWord() {
        // 生成Word文档逻辑
        viewModel.exportToWord(result: result) { success, filePath in
            if success, let path = filePath {
                // 添加到历史记录
                let record = ScanRecord(
                    id: UUID(),
                    timestamp: Date(),
                    wordFilePath: path,
                    previewText: result.recognizedText,
                    detectedLanguage: result.detectedLanguage
                )
                appState.addScanRecord(record)
                
                showExportSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showExportSuccess = false
                }
            }
        }
    }
}

// MARK: - 水印视图
struct WatermarkView: View {
    var body: some View {
        Text("扫描图文、多语言翻译、pdf转word就用 极速扫描app")
            .font(.caption)
            .foregroundColor(.gray.opacity(0.6))
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(8)
    }
}

// MARK: - 操作按钮
struct ActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
        }
    }
}
