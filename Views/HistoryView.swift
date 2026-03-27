//
// HistoryView.swift
// 历史记录界面 — SwiftData 驱动 + QuickLook 预览
//

import SwiftUI
import SwiftData
import QuickLook

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    @Query(sort: \ScanRecord.createdAt, order: .reverse)
    private var records: [ScanRecord]

    @Environment(\.modelContext) private var modelContext

    @State private var quickLookURL: URL?
    @State private var showQuickLook = false
    @State private var showUsageLimit = false

    // 免费用户只展示最近 3 条，会员展示最近 20 条
    static let freeLimit = 3
    static let vipLimit  = 20

    private var displayedRecords: [ScanRecord] {
        let isVip = subscriptionManager.isPremium
        let limit = isVip ? Self.vipLimit : Self.freeLimit
        return Array(records.prefix(limit))
    }

    private var isVip: Bool { subscriptionManager.isPremium }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()

                if !appState.isLoggedIn {
                    // 未登录空态
                    NotLoggedInEmptyState()
                } else if records.isEmpty {
                    // 已登录但无记录
                    EmptyHistoryState()
                } else {
                    // 记录列表
                    List {
                        ForEach(displayedRecords) { record in
                            HistoryCardRow(record: record)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .onTapGesture {
                                    openRecord(record)
                                }
                        }
                        .onDelete(perform: deleteRecords)

                        // 非会员且有更多记录时展示解锁提示
                        if !isVip && records.count > Self.freeLimit {
                            VStack(spacing: 12) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(Color(hex: "#007AFF"))
                                Text("还有 \(records.count - Self.freeLimit) 条记录")
                                    .font(.system(size: 15, weight: .medium))
                                Text("开通会员，最多查看最近 \(Self.vipLimit) 条导出记录")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                Button(action: { showUsageLimit = true }) {
                                    Text("解锁 VIP")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 32)
                                        .padding(.vertical, 12)
                                        .background(
                                            LinearGradient(colors: [Color(hex: "#007AFF"), Color(hex: "#0055CC")],
                                                           startPoint: .leading, endPoint: .trailing)
                                        )
                                        .cornerRadius(16)
                                        .shadow(color: Color(hex: "#007AFF").opacity(0.35), radius: 8, x: 0, y: 4)
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .background(Color.clear)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("导出记录")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    // 条数说明
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                        Text("普通用户最多保留 \(HistoryView.freeLimit) 条，")
                            .font(.system(size: 12))
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                        + Text("会员用户")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "#007AFF"))
                        + Text("最多保留 \(HistoryView.vipLimit) 条")
                            .font(.system(size: 12))
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                    Divider()

                    // 隐私说明栏
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "#34C759"))
                            .padding(.top, 1)
                        Text("文档加密存储于本机，从不上传云端\n数据归您所有，随时可删除")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .background(Color(UIColor.systemBackground))
            }
            .quickLookPreview($quickLookURL)
            .fullScreenCover(isPresented: $showUsageLimit) {
                UsageLimitView(feature: .ocr) { showUsageLimit = false }
                    .environmentObject(subscriptionManager)
            }
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
        .background(Color(UIColor.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
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
            Text("登录后查看导出记录")
                .font(.system(size: 18, weight: .semibold))
            Text("每次导出 Word 的记录将保存在本设备")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding(40)
    }
}

// MARK: - 空历史态
struct EmptyHistoryState: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // 插图区
            ZStack {
                Circle()
                    .fill(Color(hex: "#007AFF").opacity(0.08))
                    .frame(width: 120, height: 120)
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 52, weight: .light))
                    .foregroundColor(Color(hex: "#007AFF").opacity(0.7))
            }
            .padding(.bottom, 24)

            // 标题
            Text("还没有扫描记录")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.bottom, 8)

            // 说明
            Text("扫描文字或拍照转 PDF 后\n记录会自动保存在这里")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 48)
                .padding(.bottom, 32)

            // 「开始扫描」按钮 — 切换到扫描 Tab
            Button(action: {
                // 通过 NotificationCenter 通知 ContentView 切换到 ScanView Tab
                NotificationCenter.default.post(name: .switchToScanTab, object: nil)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 17, weight: .medium))
                    Text("开始扫描")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.vertical, 16)
                .padding(.horizontal, 48)
                .background(
                    LinearGradient(colors: [Color(hex: "#007AFF"), Color(hex: "#0055CC")],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(16)
                .shadow(color: Color(hex: "#007AFF").opacity(0.35), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(ScaleButtonStyle())

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Preview
#Preview {
    HistoryView()
        .environmentObject(AppState())
        .environmentObject(SubscriptionManager())
}
