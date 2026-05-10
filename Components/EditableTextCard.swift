//
//  EditableTextCard.swift
//  SpeedScan
//
//  通用可编辑文字卡片组件
//  用于 ScanResultView（印刷体识别）和 OCRResultView（手写识别）
//

import SwiftUI

struct EditableTextCard: View {
    @Binding var text: String
    var isTranslated: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    HStack(spacing: 6) {
                        Text("\(text.count) 字")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Label("可编辑", systemImage: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#C3161B").opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider().padding(.horizontal, 16)

            TextEditor(text: $text)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.primary)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .scrollDisabled(true)
                .frame(minHeight: 200)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    EditableTextCard(text: .constant("这是一段识别出来的文字\n第二行内容"))
        .padding()
}
