//
//  OCRResultView.swift
//  SpeedScan
//
//  识别结果页：显示 Claude 识别文字，支持用户直接编辑修改错别字，可复制
//

import SwiftUI

struct OCRResultView: View {
    let initialText: String
    var onDismiss: () -> Void

    @State private var editedText: String = ""
    @State private var showCopiedToast = false

    var body: some View {
        ZStack {
            Color(hex: "#1C1C1E").ignoresSafeArea()

            VStack(spacing: 0) {
                // ── 顶部导航栏
                HStack {
                    Button("关闭") { onDismiss() }
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                    Spacer()
                    Text("识别结果")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Button("复制") { copyText() }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(hex: "#34C759"))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(hex: "#2C2C2E"))

                // ── 提示语
                HStack(spacing: 6) {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                    Text("识别结果可直接点击编辑修改")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(hex: "#1C1C1E"))

                // ── 可编辑文本区域
                TextEditor(text: $editedText)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color(hex: "#1C1C1E"))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }

            // ── 复制成功 Toast
            if showCopiedToast {
                VStack {
                    Spacer()
                    Text("已复制到剪贴板 ✓")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.78))
                        .cornerRadius(24)
                        .padding(.bottom, 60)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            editedText = initialText
        }
    }

    private func copyText() {
        UIPasteboard.general.string = editedText
        withAnimation { showCopiedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showCopiedToast = false }
        }
    }
}

#Preview {
    OCRResultView(initialText: "这是一段手写识别的示例文字\n第二行内容", onDismiss: {})
}
