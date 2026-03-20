//
// ScanResultView.swift
// 识别结果界面
//

import SwiftUI
import QuickLook
import SwiftData
import Translation

struct ScanResultView: View {
    let result: OCRResult
    @ObservedObject var viewModel: ScanViewModel

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var copySuccess = false
    @State private var isExporting = false
    @State private var exportedFileURL: URL?
    @State private var showLoginSheet = false

    // 翻译
    @State private var isTranslated = false
    @State private var translatedText: String = ""
    @State private var isTranslating = false
    @State private var showTranslationSheet = false

    // 当前展示的文字（原文 or 译文）
    private var displayText: String {
        isTranslated && !translatedText.isEmpty ? translatedText : result.recognizedText
    }

    // 是否包含非简体中文内容（显示翻译按钮的条件）
    private var hasNonSimplifiedChinese: Bool {
        !result.isChinese
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── 可滚动内容区 ──────────────────────────────────────
                ScrollView {
                    VStack(spacing: 16) {

                        // 顶部 Header
                        ThumbnailHeaderView(image: result.originalImage)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        // 文字内容卡片
                        VStack(alignment: .leading, spacing: 0) {
                            // 标题栏
                            HStack {
                                Text("识别内容")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                if isTranslated {
                                    Label("已翻译", systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.green)
                                } else {
                                    Text("\(result.recognizedText.count) 字")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            Divider().padding(.horizontal, 16)

                            // 文字内容（可长按选择）
                            SelectableTextView(text: displayText)
                                .padding(16)
                        }
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                        .padding(.horizontal, 20)

                        // 翻译按钮（有非中文内容时显示）
                        if hasNonSimplifiedChinese {
                            TranslateToggleButton(
                                isTranslated: isTranslated,
                                isTranslating: isTranslating,
                                action: handleTranslate
                            )
                            .padding(.horizontal, 20)
                        }

                        // 底部留白（给底部操作栏让位）
                        Spacer(minLength: 100)
                    }
                }

                // ── 底部固定操作栏（不随 ScrollView 滚动）─────────────
                BottomActionBar(
                    onCopy: {
                        UIPasteboard.general.string = displayText
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
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .sheet(isPresented: $showLoginSheet) {
                LoginView(isModal: true)
                    .environmentObject(appState)
            }
            .translationTask(translationConfig()) { session in
                await performTranslation(session: session)
            }
            .navigationTitle("识别结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if let url = exportedFileURL {
                            shareFile(url: url)
                        } else {
                            viewModel.alertItem = AlertItem(
                                title: Text("请先导出"),
                                message: Text("点击「导出 Word」生成文档后即可分享"),
                                dismissButton: .default(Text("好的"))
                            )
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .alert(item: $viewModel.alertItem) { alert in
                Alert(title: alert.title, message: alert.message, dismissButton: alert.dismissButton)
            }
        }
    }

    // MARK: - 翻译逻辑
    private func handleTranslate() {
        if isTranslated {
            // 切回原文
            isTranslated = false
            return
        }
        if !translatedText.isEmpty {
            // 已有缓存译文，直接切换
            isTranslated = true
            return
        }
        // 模拟器不支持 Apple Translation，给出明确提示
        #if targetEnvironment(simulator)
        viewModel.alertItem = AlertItem(
            title: Text("请在真机上使用"),
            message: Text("翻译功能依赖系统语言包，模拟器不支持，请安装到真机后使用。"),
            dismissButton: .default(Text("知道了"))
        )
        #else
        // 触发 Apple Translation
        isTranslating = true
        showTranslationSheet = true
        #endif
    }

    @State private var translationTrigger = false

    private func translationConfig() -> TranslationSession.Configuration? {
        guard showTranslationSheet else { return nil }
        return TranslationSession.Configuration(
            source: nil,  // 自动检测
            target: Locale.Language(identifier: "zh-Hans")
        )
    }

    private func performTranslation(session: TranslationSession) async {
        do {
            let response = try await session.translate(result.recognizedText)
            await MainActor.run {
                translatedText = response.targetText
                isTranslated = true
                isTranslating = false
                showTranslationSheet = false
            }
        } catch {
            await MainActor.run {
                isTranslating = false
                showTranslationSheet = false
                viewModel.alertItem = AlertItem(
                    title: Text("翻译失败"),
                    message: Text(error.localizedDescription),
                    dismissButton: .default(Text("确定"))
                )
            }
        }
    }

    // MARK: - 导出 Word
    private func exportWord() {
        guard appState.requireLoginForExport() else {
            showLoginSheet = true
            return
        }
        guard !isExporting else { return }
        isExporting = true

        Task {
            let isPremium = subscriptionManager.isPremium
            let text = displayText
            let lang = result.detectedLanguage

            let filePath = await Task.detached(priority: .userInitiated) {
                DocxExporter.export(text: text, isPremium: isPremium, fileName: "ScanResult")
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

                exportedFileURL = URL(fileURLWithPath: path)
                shareFile(url: URL(fileURLWithPath: path))
            }
        }
    }

    // MARK: - 分享文件
    private func shareFile(url: URL) {
        let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController { topVC = presented }
            topVC.present(ac, animated: true)
        }
    }
}

// MARK: - 缩略图 Header
struct ThumbnailHeaderView: View {
    let image: UIImage

    var body: some View {
        HStack(spacing: 16) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 8) {
                Text("识别完成")
                    .font(.system(size: 17, weight: .semibold))
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 15))
                    Text("文字已提取，可复制或导出")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 翻译切换按钮
struct TranslateToggleButton: View {
    let isTranslated: Bool
    let isTranslating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isTranslating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#007AFF")))
                        .scaleEffect(0.85)
                    Text("翻译中…")
                } else {
                    Image(systemName: isTranslated ? "arrow.uturn.backward.circle" : "character.bubble")
                        .font(.system(size: 15))
                    Text(isTranslated ? "切回原来的语言" : "全部翻译成简体中文")
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(Color(hex: "#007AFF"))
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(hex: "#007AFF").opacity(0.08))
            .cornerRadius(12)
        }
        .disabled(isTranslating)
    }
}

// MARK: - 支持长按选择的文本（高度完全撑开，不截断，外层 ScrollView 接管滚动）
struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false          // 禁止内部滚动，高度随内容撑开
        tv.backgroundColor = .clear
        tv.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)  // 等宽字体，制表符对齐更好看
        tv.textColor = UIColor.label
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.lineBreakMode = .byWordWrapping
        tv.textContainer.maximumNumberOfLines = 0   // 不限行数
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        // 强制重新计算高度
        uiView.invalidateIntrinsicContentSize()
        uiView.setNeedsLayout()
    }
}

// MARK: - 底部操作栏
struct BottomActionBar: View {
    let onCopy: () -> Void
    let onExportWord: () -> Void
    let copySuccess: Bool
    let isExporting: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCopy) {
                HStack(spacing: 8) {
                    Image(systemName: copySuccess ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 16))
                    Text(copySuccess ? "已复制" : "复制全文")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(Color(hex: "#007AFF"))
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(Color(hex: "#007AFF").opacity(0.1))
                .cornerRadius(12)
            }
            .animation(.easeInOut(duration: 0.2), value: copySuccess)

            Button(action: onExportWord) {
                HStack(spacing: 8) {
                    if isExporting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "doc.text")
                            .font(.system(size: 16))
                    }
                    Text(isExporting ? "生成中…" : "导出 Word")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    isExporting ? AnyView(Color.gray) : AnyView(
                        LinearGradient(
                            colors: [Color(hex: "#007AFF"), Color(hex: "#0055CC")],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                )
                .cornerRadius(12)
            }
            .disabled(isExporting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

struct AnyShape: Shape {
    private let _pathClosure: @Sendable (CGRect) -> Path
    init<S: Shape & Sendable>(_ shape: S) { _pathClosure = { shape.path(in: $0) } }
    func path(in rect: CGRect) -> Path { _pathClosure(rect) }
}
