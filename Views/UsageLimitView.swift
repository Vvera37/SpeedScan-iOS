//
//  UsageLimitView.swift
//  SpeedScan
//
//  超限提示页：大标题 + 订阅卡片
//  触发场景：OCR / 图片转PDF / PDF转Word 次数用完
//

import SwiftUI
import StoreKit

struct UsageLimitView: View {

    let feature: UsageFeature
    var onDismiss: () -> Void = {}

    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var isPurchasing = false
    @State private var purchaseError: String?
    @State private var selectedProductId: String = SubscriptionManager.yearlyProductID

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    // ── 顶部关闭按钮 ──────────────────────────────
                    HStack {
                        Spacer()
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                        }
                        .padding(.top, 20)
                        .padding(.trailing, 20)
                    }

                    // ── 图标 ──────────────────────────────────────
                    Image(systemName: "sparkles")
                        .font(.system(size: 56))
                        .foregroundColor(.orange)
                        .padding(.top, 16)
                        .padding(.bottom, 20)

                    // ── 大标题 ────────────────────────────────────
                    Text("免费次数已用完")
                        .font(.system(size: 28, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Text("AI识别费用较高，请购买VIP后继续使用")
                        .font(.system(size: 16))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)
                        .padding(.bottom, 36)

                    // ── 权益列表 ──────────────────────────────────
                    VStack(alignment: .leading, spacing: 14) {
                        LimitBenefitRow(icon: "doc.viewfinder.fill",  text: "无限次 AI 识别（印刷体+手写体）")
                        LimitBenefitRow(icon: "doc.fill",             text: "无限次图片转 PDF")
                        LimitBenefitRow(icon: "doc.text.fill",        text: "无限次 PDF 转 Word")
                        LimitBenefitRow(icon: "clock.fill",           text: "历史记录保留最近 20 条")
                        LimitBenefitRow(icon: "square.and.arrow.up.fill", text: "导出文件无水印")
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 32)

                    // ── 订阅卡片 ──────────────────────────────────
                    if subscriptionManager.products.isEmpty {
                        ProgressView()
                            .padding(.bottom, 32)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(subscriptionManager.products, id: \.id) { product in
                                LimitSubscriptionCard(
                                    product: product,
                                    isSelected: selectedProductId == product.id,
                                    isPurchasing: isPurchasing,
                                    onTap: { selectedProductId = product.id }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                        // ── 购买按钮 ──────────────────────────────
                        Button(action: {
                            if let product = subscriptionManager.products.first(where: { $0.id == selectedProductId })
                                ?? subscriptionManager.products.first {
                                purchase(product: product)
                            }
                        }) {
                            HStack(spacing: 8) {
                                if isPurchasing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black.opacity(0.7)))
                                        .scaleEffect(0.85)
                                } else {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 14))
                                }
                                let product = subscriptionManager.products.first(where: { $0.id == selectedProductId })
                                    ?? subscriptionManager.products.first
                                Text(isPurchasing ? "处理中…" : "确认协议并支付 \(product?.displayPrice ?? "")")
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
                        .disabled(isPurchasing)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                    }

                    // ── 错误提示 ──────────────────────────────────
                    if let err = purchaseError {
                        Text(err)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 8)
                    }

                    // ── 恢复购买 ──────────────────────────────────
                    Button("恢复购买") {
                        Task { await subscriptionManager.restorePurchases() }
                    }
                    .font(.footnote)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .padding(.bottom, 12)

                    // ── 会员协议区域 ──────────────────────────────
                    VStack(spacing: 6) {
                        Text("订阅将从 Apple ID 账户扣款，到期前 24 小时自动续费，可随时在「设置 > Apple ID > 订阅」取消。")
                            .font(.system(size: 11))
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        // EULA + 会员协议链接
                        HStack(spacing: 4) {
                            Text("购买即代表您同意")
                                .font(.system(size: 11))
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                            Button("《会员服务协议》") {
                                UIApplication.shared.open(
                                    URL(string: "https://vmingstudio.com/terms.html")!
                                )
                            }
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#C3161B"))
                            Text("和")
                                .font(.system(size: 11))
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                            Button("Terms of Use (EULA)") {
                                UIApplication.shared.open(
                                    URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
                                )
                            }
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#C3161B"))
                        }
                    }
                    .padding(.bottom, 40)
                }
            }

            // ── 购买中遮罩 ────────────────────────────────────────
            if isPurchasing {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.4)
                        .tint(.white)
                    Text("正在处理...")
                        .foregroundColor(.white)
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - 购买
    private func purchase(product: Product) {
        isPurchasing = true
        purchaseError = nil
        Task {
            await subscriptionManager.purchase(product: product)
            await MainActor.run {
                isPurchasing = false
                if let err = subscriptionManager.purchaseError {
                    purchaseError = err
                } else if subscriptionManager.isPremium {
                    onDismiss()
                }
            }
        }
    }
}

// MARK: - 权益行（UsageLimitView 专用，避免与 ProfileView 的 BenefitRow 重名）
private struct LimitBenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 15))
        }
    }
}

// MARK: - 订阅选择卡片（UsageLimitView 专用）
private struct LimitSubscriptionCard: View {
    let product: Product
    let isSelected: Bool
    let isPurchasing: Bool
    let onTap: () -> Void

    var isYearly: Bool { product.id.contains("yearly") }

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(isYearly ? "年度会员" : "月度会员")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(isSelected ? Color(hex: "#FF6B00") : .primary)
                        if isYearly {
                            Text("推荐")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange)
                                .cornerRadius(8)
                        }
                    }
                    Text(isYearly ? "无限畅用，合算更多" : "按月订阅，随时取消")
                        .font(.system(size: 13))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(isSelected ? Color(hex: "#FF6B00") : .primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected
                        ? Color(hex: "#FF6B00").opacity(0.15)
                        : Color(UIColor.tertiarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color(hex: "#FFB800") : Color(UIColor.separator), lineWidth: isSelected ? 2 : 0.5)
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .disabled(isPurchasing)
        .buttonStyle(.plain)
    }
}

#Preview {
    UsageLimitView(feature: .ocr)
        .environmentObject(SubscriptionManager())
}
