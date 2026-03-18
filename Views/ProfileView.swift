//
// ProfileView.swift
// 「我的」Tab — 会员购买 + 账号信息 + StoreKit 2
//

import SwiftUI
import StoreKit

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showLogoutConfirm = false
    @State private var showLoginSheet = false
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // MARK: 用户信息卡
                        UserInfoCard(
                            phone: appState.userPhone,
                            isLoggedIn: appState.isLoggedIn,
                            isPremium: subscriptionManager.isPremium
                        ) {
                            showLoginSheet = true
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                        // MARK: 会员卡
                        if subscriptionManager.isPremium {
                            // 已是会员：展示状态 + 续费选项
                            PremiumStatusCard(
                                subscriptionManager: subscriptionManager
                            )
                            .padding(.horizontal, 20)
                        } else {
                            // 未开通：展示购买卡片
                            SubscriptionCard(
                                subscriptionManager: subscriptionManager
                            ) {
                                if !appState.isLoggedIn {
                                    showLoginSheet = true
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        // MARK: 功能菜单
                        MenuSection(title: "关于应用") {
                            MenuRow(icon: "star.fill", iconColor: .yellow, title: "给我们好评") {
                                requestReview()
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
            .sheet(isPresented: $showLoginSheet) {
                LoginView(isModal: true).environmentObject(appState)
            }
            .confirmationDialog("确认退出登录？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) { appState.logout() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("退出后需要重新验证手机号")
            }
            .alert("购买失败", isPresented: .init(
                get: { subscriptionManager.purchaseError != nil },
                set: { if !$0 { subscriptionManager.purchaseError = nil } }
            )) {
                Button("确定", role: .cancel) { subscriptionManager.purchaseError = nil }
            } message: {
                Text(subscriptionManager.purchaseError ?? "")
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
    let isLoggedIn: Bool
    let isPremium: Bool
    let onLoginTap: () -> Void

    var body: some View {
        Button(action: { if !isLoggedIn { onLoginTap() } }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isPremium
                              ? Color.yellow.opacity(0.2)
                              : Color(hex: "#007AFF").opacity(0.15))
                        .frame(width: 60, height: 60)
                    Image(systemName: isPremium ? "crown.fill" : "person.fill")
                        .font(.system(size: 26))
                        .foregroundColor(isPremium ? .yellow : Color(hex: "#007AFF"))
                }

                VStack(alignment: .leading, spacing: 6) {
                    if !isLoggedIn {
                        Text("未登录")
                            .font(.system(size: 18, weight: .semibold))
                        Text("点击登录，保障数据安全")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    } else {
                        Text(phone.maskedPhone)
                            .font(.system(size: 18, weight: .semibold))
                        if isPremium {
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.yellow)
                                Text("尊贵会员")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                        } else {
                            Text("免费用户")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
                if !isLoggedIn {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .padding(20)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 已开通会员卡（可续费）
struct PremiumStatusCard: View {
    @ObservedObject var subscriptionManager: SubscriptionManager
    @State private var selectedPlan: Plan = .monthly

    // 根据枚举取对应 Product
    private var selectedProduct: Product? {
        selectedPlan == .monthly
            ? subscriptionManager.monthlyProduct
            : subscriptionManager.yearlyProduct
    }

    var body: some View {
        VStack(spacing: 16) {
            // 顶部状态
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.yellow.opacity(0.2))
                        .frame(width: 48, height: 48)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.yellow)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("尊贵会员")
                            .font(.system(size: 17, weight: .bold))
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 15))
                    }
                    if let expiry = subscriptionManager.expiryDate {
                        Text("有效期至 \(expiry.formatted(.dateTime.year().month().day()))")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            Divider()

            // 续费选项
            Text("续费会员")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                PriceCard(
                    title: "月度会员",
                    price: subscriptionManager.monthlyProduct?.displayPrice ?? "--",
                    period: "/月",
                    tag: nil,
                    isSelected: selectedPlan == .monthly
                ) {
                    selectedPlan = .monthly
                }
                PriceCard(
                    title: "年度会员",
                    price: subscriptionManager.yearlyProduct?.displayPrice ?? "--",
                    period: "/年",
                    tag: "省66%",
                    isSelected: selectedPlan == .yearly
                ) {
                    selectedPlan = .yearly
                }
            }

            // 购买按钮
            Button(action: {
                if let product = selectedProduct {
                    Task { await subscriptionManager.purchase(product: product) }
                }
            }) {
                HStack(spacing: 8) {
                    if subscriptionManager.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 15))
                    }
                    Text(subscriptionManager.isLoading ? "处理中…" : "马上续费")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#FF9500"), Color(hex: "#FF6B00")],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .cornerRadius(13)
                
            }
            .disabled(subscriptionManager.isLoading)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.yellow.opacity(0.08), Color.orange.opacity(0.05)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 未开通订阅购买卡片
struct SubscriptionCard: View {
    @ObservedObject var subscriptionManager: SubscriptionManager
    @State private var selectedPlan: Plan = .monthly
    let onNeedLogin: () -> Void

    private var selectedProduct: Product? {
        selectedPlan == .monthly
            ? subscriptionManager.monthlyProduct
            : subscriptionManager.yearlyProduct
    }

    var body: some View {
        VStack(spacing: 16) {
            // 标题
            HStack {
                Image(systemName: "crown.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 20))
                Text("开通会员")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
            }

            // 会员权益
            VStack(spacing: 10) {
                BenefitRow(icon: "doc.text.fill", iconColor: Color(hex: "#007AFF"), text: "无水印导出 Word 文档")
                // 多语言翻译功能暂时下线，一期不做
                // BenefitRow(icon: "character.bubble.fill", iconColor: Color(hex: "#34C759"), text: "多语言翻译无限制")
                BenefitRow(icon: "doc.richtext.fill", iconColor: Color(hex: "#FF9500"), text: "PDF 多页批量转换")
            }

            Divider()

            // 价格卡片选择
            HStack(spacing: 12) {
                PriceCard(
                    title: "月度会员",
                    price: subscriptionManager.monthlyProduct?.displayPrice ?? "--",
                    period: "/月",
                    tag: nil,
                    isSelected: selectedPlan == .monthly
                ) {
                    selectedPlan = .monthly
                }
                PriceCard(
                    title: "年度会员",
                    price: subscriptionManager.yearlyProduct?.displayPrice ?? "--",
                    period: "/年",
                    tag: "省66%",
                    isSelected: selectedPlan == .yearly
                ) {
                    selectedPlan = .yearly
                }
            }

            // 主购买按钮
            Button(action: {
                if let product = selectedProduct {
                    Task { await subscriptionManager.purchase(product: product) }
                } else {
                    onNeedLogin()
                }
            }) {
                HStack(spacing: 8) {
                    if subscriptionManager.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black.opacity(0.7)))
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 15))
                    }
                    Text(subscriptionManager.isLoading ? "处理中…" : "马上成为尊贵的VIP")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.black.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#FFD60A"), Color(hex: "#FF9500")],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .cornerRadius(13)
                
            }
            .disabled(subscriptionManager.isLoading)
            .buttonStyle(ScaleButtonStyle())


        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 5)
    }
}

// MARK: - 订阅套餐枚举
enum Plan {
    case monthly, yearly
}

// MARK: - 价格选择卡片（带选中态）
struct PriceCard: View {
    let title: String
    let price: String
    let period: String
    let tag: String?
    let isSelected: Bool
    let action: () -> Void

    // 选中：金色/橙色边框 + 背景略加深；未选中：灰色背景无边框
    private var selectedBorderColor: Color { Color(hex: "#FFB800") }
    private var selectedBgColor: Color { Color(hex: "#FFF8E7") }   // 暖黄底，略深于白
    private var unselectedBgColor: Color { Color(hex: "#F5F5F5") } // 浅灰，无边框

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? Color(hex: "#FF8C00") : .secondary)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(price == "--" ? "--" : price)
                        .font(.system(size: isSelected ? 26 : 22, weight: .bold))
                    if price != "--" {
                        Text(period)
                            .font(.system(size: 12))
                    }
                }
                .foregroundColor(isSelected ? Color(hex: "#FF6B00") : .primary)

                if let tag = tag {
                    Text(tag)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(isSelected ? Color(hex: "#FFB800").opacity(0.2) : Color.yellow)
                        .foregroundColor(isSelected ? Color(hex: "#FF6B00") : .black)
                        .cornerRadius(5)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, isSelected ? 22 : 16)
            .background(isSelected ? selectedBgColor : unselectedBgColor)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? selectedBorderColor : Color.clear,
                        lineWidth: 2
                    )
            )
            .scaleEffect(isSelected ? 1.04 : 0.97)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 权益行
struct BenefitRow: View {
    let icon: String
    let iconColor: Color
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(iconColor)
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
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
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
