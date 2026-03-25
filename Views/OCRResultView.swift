//
//  OCRResultView.swift
//  SpeedScan
//
//  Claude Vision 识别结果页
//  UI 风格与 ScanResultView 保持一致：白底卡片 + NavigationStack + 底部操作栏
//  支持用户直接编辑修改错别字
//

import SwiftUI

struct OCRResultView: View {
    let initialText: String
    var onDismiss: () -> Void

    @State private var editedText: String = ""
    @State private var copySuccess = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── 可滚动内容区
                ScrollView {
                    LazyVStack(spacing: 16) {

                        // 顶部 Header（复用 ScanResultView 同款）
                        OCRResultHeaderView()
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        // 文字编辑卡片
                        OCREditableTextCard(editedText: $editedText)
                            .padding(.horizontal, 20)

                        Spacer(minLength: 100)
                    }
                }

                // ── 底部操作栏（复用 ScanResultView 同款样式）
                OCRBottomActionBar(
                    onCopy: {
                        UIPasteboard.general.string = editedText
                        withAnimation { copySuccess = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { copySuccess = false }
                        }
                    },
                    copySuccess: copySuccess
                )
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("识别结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { onDismiss() }
                }
            }
        }
        .onAppear {
            editedText = initialText
        }
    }
}

// MARK: - 顶部 Header
struct OCRResultHeaderView: View {
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "#007AFF").opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 36))
                    .foregroundColor(Color(hex: "#007AFF"))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("识别完成").font(.system(size: 17, weight: .semibold))
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 15))
                    Text("可直接点击编辑修改错别字")
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

// MARK: - 可编辑文字卡片
struct OCREditableTextCard: View {
    @Binding var editedText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("识别内容").font(.system(size: 14, weight: .semibold)).foregroundColor(.secondary)
                Spacer()
                Label("可编辑", systemImage: "pencil")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#007AFF").opacity(0.8))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider().padding(.horizontal, 16)

            TextEditor(text: $editedText)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.primary)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 200)
                .padding(16)
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 底部操作栏
struct OCRBottomActionBar: View {
    let onCopy: () -> Void
    let copySuccess: Bool

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
                .frame(maxWidth: .infinity)
                .background(Color(hex: "#007AFF").opacity(0.1))
                .cornerRadius(12)
            }
            .animation(.easeInOut(duration: 0.2), value: copySuccess)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Color.white.shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -4))
    }
}

#Preview {
    OCRResultView(initialText: "这是一段手写识别的示例文字\n第二行内容\n第三行，可以直接编辑", onDismiss: {})
}
