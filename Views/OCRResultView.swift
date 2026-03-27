//
//  OCRResultView.swift
//  SpeedScan
//
//  Claude Vision 识别结果页
//  UI 风格与 ScanResultView 保持一致
//  支持用户直接编辑修改错别字，可复制、导出 Word
//

import SwiftUI
import SwiftData

struct OCRResultView: View {
    let initialText: String
    let originalImage: UIImage
    var onDismiss: () -> Void

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.modelContext) private var modelContext

    @State private var editedText: String = ""
    @State private var copySuccess = false
    @State private var isExporting = false
    @State private var showLoginSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── 滚动区（外滑动，不做内层 TextEditor 滚动）
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        // 顶部缩略图 Header（复用 ScanResultView 同款）
                        ThumbnailHeaderView(image: originalImage)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        // 文字编辑卡片（复用 Components/EditableTextCard）
                        EditableTextCard(text: $editedText)
                            .padding(.horizontal, 20)

                        Spacer(minLength: 100)
                    }
                }

                // ── 底部操作栏（复制 + 导出 Word，与 ScanResultView 一致）
                HStack(spacing: 12) {
                    Button(action: copyText) {
                        HStack(spacing: 8) {
                            Image(systemName: copySuccess ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.system(size: 16))
                            Text(copySuccess ? "已复制" : "复制全文")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(Color(hex: "#007AFF"))
                        .padding(.vertical, 14).padding(.horizontal, 16)
                        .background(Color(hex: "#007AFF").opacity(0.1))
                        .cornerRadius(12)
                    }
                    .animation(.easeInOut(duration: 0.2), value: copySuccess)

                    Button(action: exportWord) {
                        HStack(spacing: 8) {
                            if isExporting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "doc.text").font(.system(size: 16))
                            }
                            Text(isExporting ? "生成中…" : "导出 Word")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(
                            isExporting ? AnyView(Color.gray) :
                            AnyView(LinearGradient(
                                colors: [Color(hex: "#007AFF"), Color(hex: "#0055CC")],
                                startPoint: .leading, endPoint: .trailing
                            ))
                        )
                        .cornerRadius(12)
                    }
                    .disabled(isExporting)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .background(Color(UIColor.systemBackground).shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -4))
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("识别结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { onDismiss() }
                }
            }
            .sheet(isPresented: $showLoginSheet) {
                LoginView(isModal: true).environmentObject(appState)
            }
        }
        .onAppear { editedText = initialText }
    }

    private func copyText() {
        UIPasteboard.general.string = editedText
        withAnimation { copySuccess = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copySuccess = false }
        }
    }

    private func exportWord() {
        guard appState.requireLoginForExport() else { showLoginSheet = true; return }
        guard !isExporting else { return }
        isExporting = true
        let isPremium = subscriptionManager.isPremium
        let text = editedText
        Task {
            let filePath = await Task.detached(priority: .userInitiated) {
                DocxExporter.export(text: text, isPremium: isPremium, fileName: "ScanResult")
            }.value
            await MainActor.run {
                isExporting = false
                guard let path = filePath else { return }
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
                modelContext.insert(ScanRecord(
                    wordFilePath: path, wordFileSize: fileSize,
                    textPreview: String(text.prefix(200)),
                    detectedLanguage: "zh-Hans"
                ))
                try? modelContext.save()
                shareFile(url: URL(fileURLWithPath: path))
            }
        }
    }

    private func shareFile(url: URL) {
        let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            var top = root
            while let presented = top.presentedViewController { top = presented }
            top.present(ac, animated: true)
        }
    }
}

#Preview {
    OCRResultView(
        initialText: "这是一段手写识别的示例文字\n第二行内容\n第三行，可以直接编辑",
        originalImage: UIImage(systemName: "doc.text.viewfinder") ?? UIImage(),
        onDismiss: {}
    )
    .environmentObject(AppState())
    .environmentObject(SubscriptionManager())
}
