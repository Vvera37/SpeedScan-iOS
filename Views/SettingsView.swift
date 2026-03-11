//
// 设置界面 - 会员购买、账号管理
//

import SwiftUI
import StoreKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showLogoutConfirm = false
    @State private var showPurchaseSuccess = false
    
    var body: some View {
        NavigationView {
            List {
                // 会员状态区
                Section(header: Text("会员状态")) {
                    if appState.isPremium {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.yellow)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("已开通会员")
                                    .fontWeight(.semibold)
                                Text("有效期至: 2026-12-31") // 实际应从后端获取
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "crown")
                                    .foregroundColor(.gray)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("未开通会员")
                                        .foregroundColor(.secondary)
                                    Text(NSLocalizedString("premium_benefits", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            
                            HStack(spacing: 12) {
                                PriceButton(
                                    price: "¥12",
                                    period: "/年",
                                    subtitle: "省66%",
                                    isRecommended: true,
                                    action: { purchaseSubscription(yearly: true) }
                                )
                                
                                PriceButton(
                                    price: "¥2",
                                    period: "/月",
                                    subtitle: nil,
                                    isRecommended: false,
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
                        Text(UserDefaults.standard.string(forKey: "user_phone")?.maskedPhone ?? "")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("登录有效期")
                        Spacer()
                        if let expiry = appState.sessionExpiry {
                            Text(formatDate(expiry))
                                .foregroundColor(.secondary)
                        } else {
                            Text("未登录")
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
                    
                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        HStack {
                            Text("隐私政策")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Link(destination: URL(string: "https://example.com/terms")!) {
                        HStack {
                            Text("用户协议")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // 退出登录
                Section {
                    Button(action: { showLogoutConfirm = true }) {
                        Text(NSLocalizedString("logout", comment: ""))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle(NSLocalizedString("settings_title", comment: ""))
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
            .overlay(
                // 购买成功提示
                VStack {
                    if showPurchaseSuccess {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("购买成功！")
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(radius: 5)
                        Spacer()
                    }
                }
                .padding(.top, 100)
            )
        }
    }
    
    // MARK: - 购买订阅
    private func purchaseSubscription(yearly: Bool) {
        // 实际应调用StoreKit
        // 这里模拟购买成功
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            appState.isPremium = true
            showPurchaseSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showPurchaseSuccess = false
            }
        }
    }
    
    // MARK: - 退出登录
    private func logout() {
        appState.isLoggedIn = false
        appState.isPremium = false
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
    let subtitle: String?
    let isRecommended: Bool
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
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isRecommended ?
                    LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .leading, endPoint: .trailing) :
                    LinearGradient(gradient: Gradient(colors: [.gray, .gray.opacity(0.8)]), startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(10)
        }
    }
}

// MARK: - 手机号脱敏
extension String {
    var maskedPhone: String {
        guard self.count == 11 else { return self }
        let prefix = self.prefix(3)
        let suffix = self.suffix(4)
        return "\(prefix)****\(suffix)"
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AppState())
    }
}
