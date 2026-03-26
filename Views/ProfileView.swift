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
    @State private var showSuccessToast = false
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // MARK: 用户信息卡（合并：账号 + 会员状态 + 权益）
                        UserInfoCard(
                            phone: appState.userPhone,
                            isLoggedIn: appState.isLoggedIn,
                            isPremium: subscriptionManager.isPremium,
                            expiryDate: subscriptionManager.expiryDate,
                            planName: subscriptionManager.currentPlanName
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
                                    .background(Color(UIColor.systemBackground))
                                    .cornerRadius(14)
                            }
                            .padding(.horizontal, 20)
                        }

                        Spacer(minLength: 40)
                    }
                }

                // ── 购买成功 Toast ────────────────────────────────
                if showSuccessToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                let plan = subscriptionManager.currentPlanName.isEmpty ? "会员" : subscriptionManager.currentPlanName
                                Text("🎉 \(plan)开通成功！")
                                    .font(.system(size: 15, weight: .semibold))
                                if let expiry = subscriptionManager.expiryDate {
                                    Text("有效期至 \(expiry.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 4)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
                }
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showLoginSheet) {
                LoginView(isModal: true).environmentObject(appState)
            }
            .alert("确认退出登录？", isPresented: $showLogoutConfirm) {
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
            .onChange(of: subscriptionManager.showPurchaseSuccess) { _, newValue in
                if newValue {
                    subscriptionManager.showPurchaseSuccess = false
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showSuccessToast = true
                    }
                    // 3 秒后自动消失
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showSuccessToast = false
                        }
                    }
                }
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

// MARK: - 用户信息卡
// MARK: - 用户信息卡（合并版：账号 + 会员状态 + 权益）
struct UserInfoCard: View {
    let phone: String
    let isLoggedIn: Bool
    let isPremium: Bool
    let expiryDate: Date?
    let planName: String
    let onLoginTap: () -> Void

    var body: some View {
        Button(action: { if !isLoggedIn { onLoginTap() } }) {
            VStack(spacing: 0) {
                // ── 顶部：头像 + 账号信息 ──────────────────────────
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(isPremium
                                  ? LinearGradient(colors: [Color.yellow.opacity(0.3), Color.orange.opacity(0.2)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                  : LinearGradient(colors: [Color(hex: "#007AFF").opacity(0.15), Color(hex: "#007AFF").opacity(0.08)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 60, height: 60)
                        Image(systemName: isPremium ? "crown.fill" : "person.fill")
                            .font(.system(size: 26))
                            .foregroundColor(isPremium ? .yellow : Color(hex: "#007AFF"))
                    }

                    VStack(alignment: .leading, spacing: 5) {
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
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.orange)
                                    let label = planName.isEmpty ? "尊贵会员" : planName
                                    Text(label)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.orange)
                                    if let expiry = expiryDate {
                                        Text("· 有效期至 \(expiry.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else {
                                Text("免费用户 · 功能受限")
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

                // ── 会员权益列表（仅会员展示）────────────────────────
                if isPremium {
                    Divider().padding(.horizontal, 20)

                    VStack(spacing: 10) {
                        HStack(spacing: 0) {
                            VIPBadgeItem(icon: "doc.viewfinder.fill", text: "AI 识别无限次")
                            VIPBadgeItem(icon: "doc.fill",            text: "图片转 PDF")
                            VIPBadgeItem(icon: "doc.text.fill",       text: "PDF 转 Word")
                            VIPBadgeItem(icon: "square.and.arrow.up.fill", text: "无水印导出")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                }
            }
            .background(
                isPremium
                    ? AnyView(LinearGradient(
                        colors: [Color.yellow.opacity(0.07), Color.orange.opacity(0.04)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyView(Color(UIColor.systemBackground))
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isPremium ? Color.yellow.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 会员权益 Badge 小项
private struct VIPBadgeItem: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.orange)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 已开通会员卡（续费选项）
struct PremiumStatusCard: View {
    @ObservedObject var subscriptionManager: SubscriptionManager
    @State private var selectedPlan: Plan = .yearly  // 默认选年度（更划算）

    private var selectedProduct: Product? {
        selectedPlan == .monthly
            ? subscriptionManager.monthlyProduct
            : subscriptionManager.yearlyProduct
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("续费会员")
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(.primary)

            HStack(spacing: 12) {
                PriceCard(
                    title: "月度会员",
                    price: subscriptionManager.monthlyProduct?.displayPrice ?? "¥2",
                    period: "/月",
                    tag: nil,
                    isSelected: selectedPlan == .monthly
                ) { selectedPlan = .monthly }
                PriceCard(
                    title: "年度会员",
                    price: subscriptionManager.yearlyProduct?.displayPrice ?? "¥12",
                    period: "/年",
                    tag: "省66%",
                    isSelected: selectedPlan == .yearly
                ) { selectedPlan = .yearly }
            }

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
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                    }
                    Text(subscriptionManager.isLoading ? "处理中…" : "立即续费")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [Color(hex: "#FF9500"), Color(hex: "#FF6B00")],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(13)
            }
            .disabled(subscriptionManager.isLoading)
        }
        .padding(20)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
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
                Text("扫描鸡专业版")
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
                    price: subscriptionManager.monthlyProduct?.displayPrice ?? "¥2",
                    period: "/月",
                    tag: nil,
                    isSelected: selectedPlan == .monthly
                ) {
                    selectedPlan = .monthly
                }
                PriceCard(
                    title: "年度会员",
                    price: subscriptionManager.yearlyProduct?.displayPrice ?? "¥12",
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
                    Text(subscriptionManager.isLoading ? "处理中…" : "立即解锁高级功能")
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
        .background(Color(UIColor.systemBackground))
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
                        .font(.system(size: 24, weight: .bold))
                    if price != "--" {
                        Text(period)
                            .font(.system(size: 12))
                    }
                }
                .foregroundColor(isSelected ? Color(hex: "#FF6B00") : .primary)

                // 无论有无 tag，始终占同等高度，确保两张卡片一样高
                Text(tag ?? " ")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tag != nil
                        ? (isSelected ? Color(hex: "#FFB800").opacity(0.2) : Color.yellow)
                        : Color.clear)
                    .foregroundColor(tag != nil
                        ? (isSelected ? Color(hex: "#FF6B00") : .black)
                        : .clear)
                    .cornerRadius(5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(isSelected ? selectedBgColor : unselectedBgColor)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? selectedBorderColor : Color.clear,
                        lineWidth: 2
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
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
            .background(Color(UIColor.systemBackground))
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
