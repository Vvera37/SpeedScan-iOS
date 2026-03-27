//
// ContentView.swift
// 主入口：支持访客模式，登录后切换到完整功能
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.isLoggedIn || appState.isGuestMode {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isLoggedIn)
    }
}

// MARK: - 主标签页
struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ScanView()
                .tabItem {
                    Label("扫描", systemImage: "camera.viewfinder")
                }
                .tag(0)

            HistoryView()
                .tabItem {
                    Label("导出", systemImage: "clock")
                }
                .tag(1)

            ProfileView()
                .tabItem {
                    Label("我的", systemImage: "person.circle")
                }
                .tag(2)
        }
        .accentColor(Color(hex: "#007AFF"))
        .onReceive(NotificationCenter.default.publisher(for: .switchToScanTab)) { _ in
            selectedTab = 0
        }
    }
}

// MARK: - Notification 扩展
extension Notification.Name {
    static let switchToScanTab = Notification.Name("switchToScanTab")
}

// MARK: - Preview
#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(SubscriptionManager())
}
