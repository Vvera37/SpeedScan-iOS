//
// 主界面
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Group {
            if !appState.isLoggedIn {
                LoginView()
            } else {
                MainTabView()
            }
        }
        .onAppear {
            appState.checkSession()
        }
    }
}

// MARK: - 主标签页
struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ScanView()
                .tabItem {
                    Image(systemName: "camera.fill")
                    Text(NSLocalizedString("tab_scan", comment: ""))
                }
                .tag(0)
            
            HistoryView()
                .tabItem {
                    Image(systemName: "doc.text.fill")
                    Text(NSLocalizedString("tab_history", comment: ""))
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text(NSLocalizedString("tab_settings", comment: ""))
                }
                .tag(2)
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environmentObject(AppState())
}
