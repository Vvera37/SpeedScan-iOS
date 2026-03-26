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
                        BenefitRow(icon: "doc.viewfinder.fill",  text: "无限次 AI 识别（印刷体+手写体）")
                        BenefitRow(icon: "doc.fill",             text: "无限次图片转 PDF")
                        BenefitRow(icon: "doc.text.fill",        text: "无限次 PDF 转 Word")
                        BenefitRow(icon: "clock.fill",           text: "历史记录保留最近 20 条")
                        BenefitRow(icon: "square.and.arrow.up.fill", text: "导出文件无水印")
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
                                SubscriptionCard(
                                    product: product,
                                    isPurchasing: isPurchasing,
                                    onTap: { purchase(product: product) }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
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
                    .padding(.bottom, 8)

                    // ── 条款说明 ──────────────────────────────────
                    Text("订阅将从 Apple ID 账户扣款。可随时在「设置 > Apple ID > 订阅」取消。")
                        .font(.system(size: 11))
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
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

// MARK: - 权益行
private struct BenefitRow: View {
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

// MARK: - 订阅卡片
private struct SubscriptionCard: View {
    let product: Product
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
                    .foregroundColor(isYearly ? .orange : .primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isYearly ? Color.orange : Color.clear, lineWidth: 2)
                    )
            )
        }
        .disabled(isPurchasing)
        .buttonStyle(.plain)
    }
}

#Preview {
    UsageLimitView(feature: .ocr)
        .environmentObject(SubscriptionManager())
}
