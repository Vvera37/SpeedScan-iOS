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
                    Text(LocalizedStringKey("tab_scan"))
                }
                .tag(0)
            
            HistoryView()
                .tabItem {
                    Image(systemName: "doc.text.fill")
                    Text(LocalizedStringKey("tab_history"))
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text(LocalizedStringKey("tab_settings"))
                }
                .tag(2)
        }
    }
}
