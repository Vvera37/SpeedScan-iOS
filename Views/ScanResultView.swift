//
// ScanResultView.swift
// 识别结果界面 — 精修 UI
//

import SwiftUI
import QuickLook
import SwiftData

struct ScanResultView: View {
    let result: OCRResult
    @ObservedObject var viewModel: ScanViewModel

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showTranslation = false
    @State private var translatedText: String = ""
    @State private var isTranslating = false
    @State private var copySuccess = false
    @State private var exportSuccess = false
    @State private var isExporting = false
    @State private var exportedFileURL: URL?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(hex: "#F2F2F7").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        // MARK: 顶部缩略图 + 准确率 Badge
                        ThumbnailHeaderView(
                            image: result.originalImage,
                            confidence: result.confidence
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                        // MARK: 文字内容区
                        VStack(alignment: .leading, spacing: 0) {
                            // 头部：字数统计
                            HStack {
                                Text("识别内容")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(result.recognizedText.count) 字")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            Divider().padding(.horizontal, 16)

                            // 可选择文字
                            SelectableTextView(text: result.recognizedText)
                                .padding(16)
                        }
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                        .padding(.horizontal, 20)

                        // MARK: 翻译按钮（非中文时显示）
                        if !result.isChinese {
                            TranslateSection(
                                originalText: result.recognizedText,
                                isTranslating: $isTranslating,
                                showTranslation: $showTranslation,
                                translatedText: $translatedText
                            )
                            .padding(.horizontal, 20)
                        }

                        // 非会员水印提示
                        if !subscriptionManager.isPremium {
                            WatermarkBanner()
                                .padding(.horizontal, 20)
                        }

                        // 底部操作栏占位空间
                        Spacer(minLength: 100)
                    }
                }

                // MARK: 底部固定操作栏
                BottomActionBar(
                    onCopy: {
                        UIPasteboard.general.string = result.recognizedText
                        withAnimation { copySuccess = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { copySuccess = false }
                        }
                    },
                    onExportWord: { exportWord() },
                    copySuccess: copySuccess,
                    isExporting: isExporting
                )
            }
            .navigationTitle("识别结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        shareText(result.recognizedText)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: - 导出 Word
    private func exportWord() {
        guard !isExporting else { return }
        isExporting = true

        Task {
            let isPremium = subscriptionManager.isPremium
            let text = result.recognizedText
            let lang = result.detectedLanguage

            let filePath = await Task.detached(priority: .userInitiated) {
                DocxExporter.export(
                    text: text,
                    isPremium: isPremium,
                    fileName: "ScanResult"
                )
            }.value

            await MainActor.run {
                isExporting = false

                guard let path = filePath else {
                    viewModel.alertItem = AlertItem(
                        title: Text("导出失败"),
                        message: Text("生成 Word 文档时发生错误，请重试"),
                        dismissButton: .default(Text("确定"))
                    )
                    return
                }

                // 保存到 SwiftData 历史记录
                let preview = String(text.prefix(200))
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
                let record = ScanRecord(
                    wordFilePath: path,
                    wordFileSize: fileSize,
                    textPreview: preview,
                    detectedLanguage: lang
                )
                modelContext.insert(record)
                try? modelContext.save()

                // 弹出系统分享面板
                exportedFileURL = URL(fileURLWithPath: path)
                shareFile(url: URL(fileURLWithPath: path))

                withAnimation { exportSuccess = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { exportSuccess = false }
                }
            }
        }
    }

    // MARK: - 分享文件
    private func shareFile(url: URL) {
        let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            // 找到最顶层 VC
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(ac, animated: true)
        }
    }

    // MARK: - 分享文字
    private func shareText(_ text: String) {
        let ac = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(ac, animated: true)
        }
    }
}

// MARK: - 缩略图 + 准确率 Badge
struct ThumbnailHeaderView: View {
    let image: UIImage
    let confidence: Double

    var body: some View {
        HStack(spacing: 16) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 10) {
                Text("识别完成")
                    .font(.system(size: 17, weight: .semibold))

                // 准确率 Badge
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("准确率 \(Int(confidence * 100))%")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 支持长按选择的文本
struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.font = UIFont.systemFont(ofSize: 16)
        tv.textColor = UIColor.label
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
    }
}

// MARK: - 翻译区域
struct TranslateSection: View {
    let originalText: String
    @Binding var isTranslating: Bool
    @Binding var showTranslation: Bool
    @Binding var translatedText: String

    var body: some View {
        VStack(spacing: 0) {
            Button(action: performTranslate) {
                HStack {
                    Image(systemName: "character.bubble")
                        .font(.system(size: 16))
                    Text("翻译为中文")
                        .font(.system(size: 15, weight: .medium))
                    if isTranslating {
                        Spacer()
                        ProgressView()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#007AFF").opacity(0.08))
                .foregroundColor(Color(hex: "#007AFF"))
            }
            .disabled(isTranslating)
            .cornerRadius(showTranslation ? 0 : 14)
            .clipShape(
                showTranslation
                    ? AnyShape(RoundedCorner(radius: 14, corners: [.topLeft, .topRight]))
                    : AnyShape(RoundedRectangle(cornerRadius: 14))
            )

            if showTranslation && !translatedText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("翻译结果")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(translatedText)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedCorner(radius: 14, corners: [.bottomLeft, .bottomRight]))
            }
        }
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
    }

    private func performTranslate() {
        guard !isTranslating else { return }
        isTranslating = true
        // TODO: 接入真实翻译 API（Apple Translate / 百度 / 腾讯）
        // 这里使用模拟翻译作为占位
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.8) {
            let result = "[翻译功能待接入]\n\n原文：\n\(originalText.prefix(200))"
            DispatchQueue.main.async {
                translatedText = result
                showTranslation = true
                isTranslating = false
            }
        }
    }
}

// MARK: - 水印横幅
struct WatermarkBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundColor(.orange)
            Text("扫描图文、多语言翻译、pdf转word就用 极速扫描app")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(10)
    }
}

// MARK: - 底部操作栏
struct BottomActionBar: View {
    let onCopy: () -> Void
    let onExportWord: () -> Void
    let copySuccess: Bool
    let isExporting: Bool

    var body: some View {
        HStack(spacing: 16) {
            // 复制全文
            Button(action: onCopy) {
                HStack(spacing: 8) {
                    Image(systemName: copySuccess ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 17))
                    Text(copySuccess ? "已复制" : "复制全文")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(Color(hex: "#007AFF"))
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(hex: "#007AFF").opacity(0.1))
                .cornerRadius(12)
            }
            .animation(.easeInOut(duration: 0.2), value: copySuccess)

            // 导出 Word
            Button(action: onExportWord) {
                HStack(spacing: 8) {
                    if isExporting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "doc.text")
                            .font(.system(size: 17))
                    }
                    Text(isExporting ? "生成中…" : "导出 Word")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    Group {
                        if isExporting {
                            Color.gray
                        } else {
                            LinearGradient(
                                colors: [Color(hex: "#007AFF"), Color(hex: "#0055CC")],
                                startPoint: .leading, endPoint: .trailing
                            )
                        }
                    }
                )
                .cornerRadius(12)
            }
            .disabled(isExporting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Color.white
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -4)
        )
    }
}

// MARK: - 圆角辅助
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

struct AnyShape: Shape {
    private let pathClosure: (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        pathClosure = shape.path(in:)
    }

    func path(in rect: CGRect) -> Path {
        pathClosure(rect)
    }
}
