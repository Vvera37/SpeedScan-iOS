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
    
    /// 动态解析当前沙盒下的完整路径（兼容 App 更新后 UUID 变化）
    var resolvedWordFilePath: String {
        // 如果存储的是绝对路径且文件存在，直接用
        if FileManager.default.fileExists(atPath: wordFilePath) {
            return wordFilePath
        }
        // 否则用文件名在当前 Documents 目录下重新拼接
        let fileName = (wordFilePath as NSString).lastPathComponent
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return wordFilePath
        }
        return docs.appendingPathComponent(fileName).path
    }

    /// Word 文件是否存在（自动兼容路径变化）
    var wordFileExists: Bool {
        FileManager.default.fileExists(atPath: resolvedWordFilePath)
    }
}
