//
// 历史记录界面
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText: String = ""
    @State private var selectedRecord: ScanRecord?
    
    var filteredRecords: [ScanRecord] {
        if searchText.isEmpty {
            return appState.scanHistory
        }
        return appState.scanHistory.filter { record in
            record.previewText.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // 搜索栏
                SearchBar(text: $searchText)
                    .padding(.horizontal)
                
                if filteredRecords.isEmpty {
                    // 空状态
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.5))
                        Text(NSLocalizedString("history_empty", comment: ""))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    // 历史列表
                    List {
                        ForEach(filteredRecords) { record in
                            HistoryRow(record: record)
                                .onTapGesture {
                                    selectedRecord = record
                                }
                        }
                        .onDelete(perform: deleteRecords)
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle(NSLocalizedString("history_title", comment: ""))
        }
    }
    
    private func deleteRecords(at offsets: IndexSet) {
        appState.scanHistory.remove(atOffsets: offsets)
        appState.saveHistory()
    }
}

// MARK: - 搜索栏
struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("搜索历史记录", text: $text)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - 历史记录行
struct HistoryRow: View {
    let record: ScanRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                LanguageTag(language: record.detectedLanguage)
            }
            
            Text(record.previewText.prefix(100) + (record.previewText.count > 100 ? "..." : ""))
                .font(.body)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 语言标签
struct LanguageTag: View {
    let language: String
    
    var displayName: String {
        switch language {
        case "zh-Hans", "zh-Hant": return "中文"
        case "en": return "English"
        case "ja": return "日本語"
        case "ko": return "한국어"
        default: return language
        }
    }
    
    var body: some View {
        Text(displayName)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(4)
    }
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
            .environmentObject(AppState())
    }
}
