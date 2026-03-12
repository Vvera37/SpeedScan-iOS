//
// ProfileView.swift
// 「我的」Tab — 会员购买 + 账号信息 + StoreKit 2
//
// ⚠️ StoreKit 测试说明：
//   真机测试需在 Xcode -> Product -> Scheme -> Edit Scheme -> Run -> StoreKit Configuration
//   中配置 .storekit 文件，或在 App Store Connect 创建对应 Product ID。
//

import SwiftUI
import StoreKit

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showLogoutConfirm = false
    @State private var showPurchaseError = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#F2F2F7").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // MARK: 用户信息卡
                        UserInfoCard(
                            phone: appState.userPhone,
                            isPremium: subscriptionManager.isPremium
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                        // MARK: 会员卡（非会员时展示购买）
                        if subscriptionManager.isPremium {
                            PremiumBadgeCard()
                                .padding(.horizontal, 20)
                        } else {
                            SubscriptionCard(
                                monthlyProduct: subscriptionManager.monthlyProduct,
                                yearlyProduct: subscriptionManager.yearlyProduct,
                                isLoading: subscriptionManager.isLoading
                            ) { product in
                                Task { await subscriptionManager.purchase(product: product) }
                            } onRestore: {
                                Task { await subscriptionManager.restorePurchases() }
                            }
                            .padding(.horizontal, 20)
                        }

                        // MARK: 功能菜单
                        MenuSection(title: "关于应用") {
                            MenuRow(icon: "star.fill", iconColor: .yellow, title: "给我们好评") {
                                if let url = URL(string: "itms-apps://itunes.apple.com/app/id0000000000?action=write-review") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            Divider().padding(.leading, 52)
                            MenuRow(icon: "doc.text", iconColor: .blue, title: "隐私政策") {
                                UIApplication.shared.open(URL(string: "https://saomiaoji.com/privacy")!)
                            }
                            Divider().padding(.leading, 52)
                            MenuRow(icon: "text.book.closed", iconColor: .green, title: "用户协议") {
                                UIApplication.shared.open(URL(string: "https://saomiaoji.com/terms")!)
                            }
                            Divider().padding(.leading, 52)
                            MenuRow(icon: "info.circle", iconColor: .gray, title: "版本号") {
                            } trailing: {
                                Text(appVersion)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 20)

                        // MARK: 退出登录
                        if appState.isLoggedIn {
                            Button(action: { showLogoutConfirm = true }) {
                                Text("退出登录")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.white)
                                    .cornerRadius(14)
                            }
                            .padding(.horizontal, 20)
                        }

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.large)
            .confirmationDialog("确认退出登录？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) { appState.logout() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("退出后需要重新验证手机号")
            }
            .alert("购买失败", isPresented: $showPurchaseError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(subscriptionManager.purchaseError ?? "")
            }
            .onChange(of: subscriptionManager.purchaseError) { _, error in
                showPurchaseError = error != nil
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

// MARK: - 用户信息卡
struct UserInfoCard: View {
    let phone: String
    let isPremium: Bool

    var body: some View {
        HStack(spacing: 16) {
            // 头像
            ZStack {
                Circle()
                    .fill(Color(hex: "#007AFF").opacity(0.15))
                    .frame(width: 60, height: 60)
                Image(systemName: "person.fill")
                    .font(.system(size: 26))
                    .foregroundColor(Color(hex: "#007AFF"))
            }

            VStack(alignment: .leading, spacing: 6) {
                if phone.isEmpty {
                    Text("未登录")
                        .font(.system(size: 18, weight: .semibold))
                } else {
                    Text(phone.maskedPhone)
                        .font(.system(size: 18, weight: .semibold))
                }
                if isPremium {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow)
                        Text("会员用户")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.orange)
                    }
                } else {
                    Text("免费用户")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 已购会员卡
struct PremiumBadgeCard: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 32))
                .foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text("已开通会员")
                    .font(.system(size: 17, weight: .semibold))
                Text("享受无水印导出 · 翻译无限制")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 24))
                .foregroundColor(.green)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.yellow.opacity(0.15), Color.orange.opacity(0.1)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - 订阅购买卡片
struct SubscriptionCard: View {
    let monthlyProduct: Product?
    let yearlyProduct: Product?
    let isLoading: Bool
    let onPurchase: (Product) -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // 标题
            HStack {
                Image(systemName: "crown.fill")
                    .foregroundColor(.yellow)
                Text("开通会员")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
            }

            // 会员权益
            VStack(spacing: 8) {
                BenefitRow(icon: "doc.text.fill", text: "无水印导出 Word 文档")
                BenefitRow(icon: "character.bubble.fill", text: "多语言翻译无限制")
                BenefitRow(icon: "doc.richtext.fill", text: "PDF 多页批量转换")
            }

            Divider()

            // 价格按钮
            HStack(spacing: 12) {
                // 月度
                SubscribePriceButton(
                    title: "月度会员",
                    price: monthlyProduct?.displayPrice ?? "¥2",
                    period: "/月",
                    tag: nil,
                    isHighlighted: false,
                    isLoading: isLoading
                ) {
                    if let product = monthlyProduct {
                        onPurchase(product)
                    }
                }

                // 年度（推荐）
                SubscribePriceButton(
                    title: "年度会员",
                    price: yearlyProduct?.displayPrice ?? "¥12",
                    period: "/年",
                    tag: "省66%",
                    isHighlighted: true,
                    isLoading: isLoading
                ) {
                    if let product = yearlyProduct {
                        onPurchase(product)
                    }
                }
            }

            // 恢复购买
            Button(action: onRestore) {
                Text("恢复购买")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 5)
    }
}

// MARK: - 权益行
struct BenefitRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "#007AFF"))
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.green)
        }
    }
}

// MARK: - 订阅价格按钮
struct SubscribePriceButton: View {
    let title: String
    let price: String
    let period: String
    let tag: String?
    let isHighlighted: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isHighlighted ? .white : .primary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(price)
                        .font(.system(size: 22, weight: .bold))
                    Text(period)
                        .font(.system(size: 12))
                }
                .foregroundColor(isHighlighted ? .white : .primary)
                if let tag = tag {
                    Text(tag)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(5)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isHighlighted
                    ? LinearGradient(colors: [Color(hex: "#007AFF"), Color(hex: "#0055CC")], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [Color(.systemGray6), Color(.systemGray5)], startPoint: .top, endPoint: .bottom)
            )
            .cornerRadius(12)
        }
        .disabled(isLoading)
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - 菜单 Section
struct MenuSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content
            }
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
        }
    }
}

// MARK: - 菜单行
struct MenuRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let action: () -> Void
    var trailing: (() -> Trailing)?

    init(icon: String, iconColor: Color, title: String, action: @escaping () -> Void, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundColor(iconColor)
                }
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                Spacer()
                if let trailing = trailing {
                    trailing()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

// 无 trailing 的便利 init
extension MenuRow where Trailing == EmptyView {
    init(icon: String, iconColor: Color, title: String, action: @escaping () -> Void) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.action = action
        self.trailing = nil
    }
}

// MARK: - 手机号脱敏
extension String {
    var maskedPhone: String {
        guard self.count >= 7 else { return self }
        let prefix = self.prefix(3)
        let suffix = self.suffix(4)
        return "\(prefix)****\(suffix)"
    }
}

// MARK: - Preview
#Preview {
    ProfileView()
        .environmentObject(AppState())
        .environmentObject(SubscriptionManager())
}
