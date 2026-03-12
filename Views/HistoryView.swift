//
// HistoryView.swift
// 历史记录界面 — SwiftData 驱动 + QuickLook 预览
//

import SwiftUI
import SwiftData
import QuickLook

struct HistoryView: View {
    @EnvironmentObject var appState: AppState

    @Query(sort: \ScanRecord.createdAt, order: .reverse)
    private var records: [ScanRecord]

    @Environment(\.modelContext) private var modelContext

    @State private var quickLookURL: URL?
    @State private var showQuickLook = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#F2F2F7").ignoresSafeArea()

                if !appState.isLoggedIn {
                    // 未登录空态
                    NotLoggedInEmptyState()
                } else if records.isEmpty {
                    // 已登录但无记录
                    EmptyHistoryState()
                } else {
                    // 记录列表
                    List {
                        ForEach(records) { record in
                            HistoryCardRow(record: record)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .onTapGesture {
                                    openRecord(record)
                                }
                        }
                        .onDelete(perform: deleteRecords)
                    }
                    .listStyle(.plain)
                    .background(Color.clear)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.large)
            .quickLookPreview($quickLookURL)
        }
    }

    // MARK: - 打开 Word 文件预览
    private func openRecord(_ record: ScanRecord) {
        guard record.wordFileExists else {
            // 文件不存在，提示
            return
        }
        quickLookURL = URL(fileURLWithPath: record.wordFilePath)
    }

    // MARK: - 删除记录
    private func deleteRecords(at offsets: IndexSet) {
        for index in offsets {
            let record = records[index]
            // 同时删除磁盘上的 Word 文件
            if record.wordFileExists {
                try? FileManager.default.removeItem(atPath: record.wordFilePath)
            }
            modelContext.delete(record)
        }
        try? modelContext.save()
    }
}

// MARK: - 历史记录卡片行
struct HistoryCardRow: View {
    let record: ScanRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // 语言标签
                Text(record.languageDisplayName)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: "#007AFF").opacity(0.1))
                    .foregroundColor(Color(hex: "#007AFF"))
                    .cornerRadius(6)

                Spacer()

                // 时间
                Text(record.formattedDate)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // 文字预览
            Text(record.textPreview.isEmpty ? "(无文字内容)" : record.textPreview)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            // 底部：Word 文件大小 + 图标
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Text(record.wordFileExists ? fileSizeString(record.wordFileSize) : "文件已删除")
                    .font(.system(size: 12))
                    .foregroundColor(record.wordFileExists ? .secondary : .red.opacity(0.7))
                Spacer()
                if record.wordFileExists {
                    Text("点击预览")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#007AFF"))
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
    }

    private func fileSizeString(_ size: Int64) -> String {
        if size < 1024 { return "\(size) B" }
        else if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        else { return String(format: "%.1f MB", Double(size) / (1024 * 1024)) }
    }
}

// MARK: - 未登录空态
struct NotLoggedInEmptyState: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 64))
                .foregroundColor(Color(hex: "#007AFF").opacity(0.6))
            Text("登录后查看历史记录")
                .font(.system(size: 18, weight: .semibold))
            Text("您的扫描历史将保存在本设备")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding(40)
    }
}

// MARK: - 空历史态
struct EmptyHistoryState: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.5))
            Text("暂无扫描记录")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.secondary)
            Text("扫描并导出 Word 后，记录会显示在这里")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Preview
#Preview {
    HistoryView()
        .environmentObject(AppState())
        .environmentObject(SubscriptionManager())
}
