//
// 极速扫描 - iOS App
// 基于SwiftUI + Vision框架的端侧OCR工具
//

import SwiftUI
import Vision
import PDFKit

@main
struct SpeedScanApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppState())
        }
    }
}

// MARK: - 应用状态管理
class AppState: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var isPremium: Bool = false
    @Published var sessionExpiry: Date?
    @Published var scanHistory: [ScanRecord] = []
    
    // 90天会话检查
    func checkSession() {
        if let expiry = sessionExpiry, expiry > Date() {
            // 自动延期90天
            sessionExpiry = Calendar.current.date(byAdding: .day, value: 90, to: Date())
            isLoggedIn = true
        } else {
            isLoggedIn = false
        }
    }
}

// MARK: - 扫描记录模型
struct ScanRecord: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let wordFilePath: String
    let previewText: String
    let detectedLanguage: String
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}
