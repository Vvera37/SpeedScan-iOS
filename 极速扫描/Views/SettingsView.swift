//
// 设置界面 - 会员购买、账号管理
//

import SwiftUI
import StoreKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showLogoutConfirm = false
    
    var body: some View {
        NavigationView {
            List {
                // 会员状态区
                Section(header: Text("会员状态")) {
                    if appState.isPremium {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.yellow)
                            Text("已开通会员")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("有效期至: 2026-12-31") // 实际应从后端获取
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "crown")
                                    .foregroundColor(.gray)
                                Text("未开通会员")
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(LocalizedStringKey("premium_benefits"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            HStack(spacing: 12) {
                                PriceButton(
                                    price: "¥12",
                                    period: "/年",
                                    action: { purchaseSubscription(yearly: true) }
                                )
                                
                                PriceButton(
                                    price: "¥2",
                                    period: "/月",
                                    action: { purchaseSubscription(yearly: false) }
                                )
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                // 账号信息
                Section(header: Text("账号信息")) {
                    HStack {
                        Text("手机号")
                        Spacer()
                        Text(UserDefaults.standard.string(forKey: "user_phone") ?? "")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("登录有效期")
                        Spacer()
                        if let expiry = appState.sessionExpiry {
                            Text(formatDate(expiry))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // 关于
                Section(header: Text("关于")) {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://apps.apple.com")!) {
                        HStack {
                            Text("给我们评分")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // 退出登录
                Section {
                    Button(action: { showLogoutConfirm = true }) {
                        Text(LocalizedStringKey("logout"))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle(LocalizedStringKey("settings_title"))
            .alert(isPresented: $showLogoutConfirm) {
                Alert(
                    title: Text("确认退出登录？"),
                    message: Text("退出后需要重新验证手机号"),
                    primaryButton: .destructive(Text("退出")) {
                        logout()
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
    }
    
    // MARK: - 购买订阅
    private func purchaseSubscription(yearly: Bool) {
        // 实际应调用StoreKit
        // 这里模拟购买成功
        appState.isPremium = true
    }
    
    // MARK: - 退出登录
    private func logout() {
        appState.isLoggedIn = false
        appState.sessionExpiry = nil
        UserDefaults.standard.removeObject(forKey: "user_phone")
        UserDefaults.standard.removeObject(forKey: "session_expiry")
    }
    
    // MARK: - 格式化日期
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - 价格按钮
struct PriceButton: View {
    let price: String
    let period: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(price)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(period)
                        .font(.caption)
                }
                .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.blue)
            .cornerRadius(10)
        }
    }
}
