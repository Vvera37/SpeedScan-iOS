//
// SettingsView.swift
// 设置页面 — 由 ProfileView 承担主要功能，此文件作为编译占位
//

import SwiftUI

/// 设置视图（主要功能已迁移到 ProfileView）
struct SettingsView: View {
    var body: some View {
        ProfileView()
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(SubscriptionManager())
}
