//
// ScanRecord.swift
// SwiftData 扫描历史记录数据模型
//

import Foundation
import SwiftData

@Model
final class ScanRecord {
    // @Attribute(.unique) 在某些版本需要特殊处理，用 UUID 自然唯一
    var id: UUID
    var createdAt: Date
    var wordFilePath: String
    var wordFileSize: Int64
    var textPreview: String       // 前200字
    var detectedLanguage: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        wordFilePath: String,
        wordFileSize: Int64 = 0,
        textPreview: String,
        detectedLanguage: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.wordFilePath = wordFilePath
        self.wordFileSize = wordFileSize
        self.textPreview = textPreview
        self.detectedLanguage = detectedLanguage
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年MM月dd日 HH:mm:ss"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: createdAt)
    }

    var languageDisplayName: String {
        switch detectedLanguage {
        case "zh-Hans", "zh-Hant", "zh": return "中文"
        case "en": return "English"
        case "ja": return "日本語"
        case "ko": return "한국어"
        default: return detectedLanguage.isEmpty ? "未知" : detectedLanguage
        }
    }
    
    /// Word 文件是否存在
    var wordFileExists: Bool {
        FileManager.default.fileExists(atPath: wordFilePath)
    }
}
