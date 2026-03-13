//
// DocxExporter.swift
// 真实 .docx 导出，基于 Open XML + ZIPFoundation
//
// 注意：ZIPFoundation 需要在 Xcode 中通过 SPM 添加依赖后才可编译使用。
// 如果尚未在 Xcode 项目中添加该依赖，编译时会报错 "No such module 'ZIPFoundation'"。
// 在 Xcode 菜单 File > Add Package Dependencies... 中粘贴以下 URL 即可：
//   https://github.com/weichsel/ZIPFoundation.git （版本 0.9.0+）
//

import Foundation
import ZIPFoundation

/// 负责生成 .docx 文件并保存到 Documents 目录
struct DocxExporter {

    // MARK: - 水印文字（非会员时插入页眉）
    private static let watermarkText = "扫描图文、多语言翻译、pdf转word就用 极速扫描app"

    // MARK: - 主入口
    /// - Parameters:
    ///   - text: 识别出的全文
    ///   - isPremium: 是否会员（控制水印）
    ///   - fileName: 文件名（不含扩展名）
    /// - Returns: 保存成功后的完整文件路径，失败则返回 nil
    static func export(text: String, isPremium: Bool, fileName: String = "ScanResult") -> String? {
        let fileManager = FileManager.default

        // 目标路径：App Documents 目录
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let docxURL = documentsURL.appendingPathComponent("\(fileName)_\(Int(Date().timeIntervalSince1970)).docx")

        // 构建内存中 docx 所需 XML 文件内容
        let documentXML = makeDocumentXML(text: text, isPremium: isPremium)
        let relsXML = makeRelsXML()
        let contentTypesXML = makeContentTypesXML()
        let wordRelsXML = makeWordRelsXML()

        // 构造 ZIP（docx 本质是 ZIP 包）
        do {
            // 先删除已有文件（如果存在）
            if fileManager.fileExists(atPath: docxURL.path) {
                try fileManager.removeItem(at: docxURL)
            }

            guard let archive = Archive(url: docxURL, accessMode: .create) else {
                return nil
            }

            // 添加各文件到压缩包
            try addEntry(archive: archive, path: "[Content_Types].xml", content: contentTypesXML)
            try addEntry(archive: archive, path: "_rels/.rels", content: relsXML)
            try addEntry(archive: archive, path: "word/_rels/document.xml.rels", content: wordRelsXML)
            try addEntry(archive: archive, path: "word/document.xml", content: documentXML)

            return docxURL.path
        } catch {
            print("[DocxExporter] 导出失败: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - ZIP 条目写入辅助
    private static func addEntry(archive: Archive, path: String, content: String) throws {
        guard let data = content.data(using: .utf8) else { return }
        let dataCount = data.count
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(dataCount)) { (position: Int64, size: Int) -> Data in
            let start = Int(position)
            let end = start + size
            return data[start..<end]
        }
    }

    // MARK: - [Content_Types].xml
    private static func makeContentTypesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """
    }

    // MARK: - _rels/.rels
    private static func makeRelsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
    }

    // MARK: - word/_rels/document.xml.rels
    private static func makeWordRelsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        </Relationships>
        """
    }

    // MARK: - word/document.xml（核心内容）
    private static func makeDocumentXML(text: String, isPremium: Bool) -> String {
        // 将文本按换行拆分成段落
        let lines = text.components(separatedBy: "\n")
        var paragraphsXML = ""

        // 非会员：页眉水印段落
        if !isPremium {
            let watermarkEscaped = escapeXML(watermarkText)
            paragraphsXML += """
            <w:p>
              <w:pPr>
                <w:jc w:val="center"/>
                <w:rPr>
                  <w:color w:val="AAAAAA"/>
                  <w:sz w:val="18"/>
                </w:rPr>
              </w:pPr>
              <w:r>
                <w:rPr>
                  <w:color w:val="AAAAAA"/>
                  <w:sz w:val="18"/>
                </w:rPr>
                <w:t>\(watermarkEscaped)</w:t>
              </w:r>
            </w:p>
            <w:p><w:r><w:t></w:t></w:r></w:p>
            """
        }

        // 正文内容段落
        for line in lines {
            let escaped = escapeXML(line)
            paragraphsXML += """
            <w:p>
              <w:r>
                <w:rPr>
                  <w:sz w:val="24"/>
                  <w:szCs w:val="24"/>
                </w:rPr>
                <w:t xml:space="preserve">\(escaped)</w:t>
              </w:r>
            </w:p>
            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
                    xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
                    xmlns:aink="http://schemas.microsoft.com/office/drawing/2016/ink"
                    xmlns:am3d="http://schemas.microsoft.com/office/drawing/2017/model3d"
                    xmlns:o="urn:schemas-microsoft-com:office:office"
                    xmlns:oel="http://schemas.microsoft.com/office/2019/extlst"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
                    xmlns:v="urn:schemas-microsoft-com:vml"
                    xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing"
                    xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
                    xmlns:w10="urn:schemas-microsoft-com:office:word"
                    xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"
                    xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml"
                    xmlns:w16cex="http://schemas.microsoft.com/office/word/2018/wordml/cex"
                    xmlns:w16cid="http://schemas.microsoft.com/office/word/2016/wordml/cid"
                    xmlns:w16="http://schemas.microsoft.com/office/word/2018/wordml"
                    xmlns:w16sdtdh="http://schemas.microsoft.com/office/word/2020/wordml/sdtdatahash"
                    xmlns:w16se="http://schemas.microsoft.com/office/word/2015/wordml/symex"
                    xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
                    xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk"
                    xmlns:wne="http://schemas.microsoft.com/office/word/2006/wordml"
                    xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
                    mc:Ignorable="w14 w15 w16se w16cid w16 w16cex w16sdtdh wp14">
          <w:body>
            \(paragraphsXML)
            <w:sectPr>
              <w:pgSz w:w="12240" w:h="15840"/>
              <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """
    }

    // MARK: - XML 特殊字符转义
    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
