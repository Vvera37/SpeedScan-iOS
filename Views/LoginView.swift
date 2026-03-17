//
// LoginView.swift
// 手机号登录 — 完整实现，含 API 调用 + Keychain 存储
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState

    @State private var phoneNumber: String = ""
    @State private var verificationCode: String = ""
    @State private var showCodeInput: Bool = false
    @State private var isLoading: Bool = false
    @State private var countdown: Int = 0
    @State private var countdownTimer: Timer?
    @State private var errorMessage: String = ""
    @State private var showError: Bool = false
    @State private var agreedToTerms: Bool = false
    @State private var isShowingAgreementToast: Bool = false

    var body: some View {
        ZStack {
            // Toast 提示
            if isShowingAgreementToast {
                VStack {
                    Spacer()
                    Text("请勾选用户隐私协议")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(24)
                        .padding(.bottom, 80)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                .zIndex(999)
                .animation(.easeInOut(duration: 0.25), value: isShowingAgreementToast)
            }

            // 背景
            LinearGradient(
                colors: [Color(hex: "#F2F2F7"), Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            // 点击空白区域收起键盘
            .onTapGesture { hideKeyboard() }

            ScrollView {
                VStack(spacing: 0) {

                    // MARK: Logo 区域
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#007AFF").opacity(0.12))
                                .frame(width: 120, height: 120)
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 56, weight: .medium))
                                .foregroundColor(Color(hex: "#007AFF"))
                        }
                        .padding(.top, 80)

                        Text("扫描鸡")
                            .font(.system(size: 34, weight: .bold))

                        Text("智能 OCR · 扫描识别 · PDF 转 Word")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 48)

                    // MARK: 表单卡片
                    VStack(spacing: 16) {
                        // 手机号输入
                        VStack(alignment: .leading, spacing: 8) {
                            Text("手机号")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                            HStack(spacing: 12) {
                                // +86 前缀
                                Text("+86")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Color(hex: "#007AFF"))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 14)
                                    .background(Color(hex: "#007AFF").opacity(0.08))
                                    .cornerRadius(10)

                                TextField("请输入手机号", text: $phoneNumber)
                                    .keyboardType(.numberPad)
                                    .textContentType(.telephoneNumber)
                                    .font(.system(size: 16))
                                    .onChange(of: phoneNumber) { _, newValue in
                                        phoneNumber = String(newValue.filter { $0.isNumber }.prefix(11))
                                    }
                            }
                            .padding(4)
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                        }

                        // 验证码输入（发送后显示）
                        if showCodeInput {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("验证码")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                HStack {
                                    TextField("请输入6位验证码", text: $verificationCode)
                                        .keyboardType(.numberPad)
                                        .font(.system(size: 16))
                                        .onChange(of: verificationCode) { _, newValue in
                                            verificationCode = String(newValue.filter { $0.isNumber }.prefix(6))
                                        }
                                    Spacer()
                                    Button(action: { Task { await sendCode() } }) {
                                        Text(countdown > 0 ? "\(countdown)s 后重发" : "重新发送")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(countdown > 0 ? .secondary : Color(hex: "#007AFF"))
                                    }
                                    .disabled(countdown > 0 || isLoading)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }

                        // 主操作按钮
                        Button(action: { Task { await primaryAction() } }) {
                            HStack(spacing: 10) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.9)
                                }
                                Text(showCodeInput ? "登录" : "获取验证码")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                isValidPhone
                                    ? LinearGradient(
                                        colors: [Color(hex: "#007AFF"), Color(hex: "#0055CC")],
                                        startPoint: .leading, endPoint: .trailing
                                      )
                                    : LinearGradient(
                                        colors: [Color.gray.opacity(0.5), Color.gray.opacity(0.4)],
                                        startPoint: .leading, endPoint: .trailing
                                      )
                            )
                            .cornerRadius(14)
                            .shadow(
                                color: isValidPhone ? Color(hex: "#007AFF").opacity(0.35) : .clear,
                                radius: 10, x: 0, y: 5
                            )
                        }
                        .disabled(!isValidPhone || isLoading)
                        .animation(.easeInOut(duration: 0.2), value: isValidPhone)
                    }
                    .padding(.horizontal, 28)

                    // MARK: 跳过登录入口
                    Button(action: {
                        hideKeyboard()
                        appState.enterGuestMode()
                    }) {
                        Text("跳过，先体验扫描功能")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .underline()
                    }
                    .padding(.top, 16)

                    // MARK: 隐私条款（需手动勾选）
                    Button(action: { agreedToTerms.toggle() }) {
                        HStack(alignment: .top, spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(agreedToTerms ? Color(hex: "#007AFF") : Color.gray.opacity(0.5), lineWidth: 1.5)
                                    .frame(width: 18, height: 18)
                                if agreedToTerms {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color(hex: "#007AFF"))
                                        .frame(width: 18, height: 18)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.top, 1)

                            Group {
                                Text("我已阅读并同意 ")
                                    .foregroundColor(.secondary)
                                + Text("《用户协议》")
                                    .foregroundColor(Color(hex: "#007AFF"))
                                + Text(" 和 ")
                                    .foregroundColor(.secondary)
                                + Text("《隐私政策》")
                                    .foregroundColor(Color(hex: "#007AFF"))
                            }
                            .font(.system(size: 12))
                            .multilineTextAlignment(.leading)
                            .onTapGesture { } // 防止文字点击冒泡到按钮
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
        }
        .alert("提示", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showCodeInput)
    }

    // MARK: - 验证手机号
    private var isValidPhone: Bool {
        let regex = "^1[3-9]\\d{9}$"
        return phoneNumber.range(of: regex, options: .regularExpression) != nil
    }

    // MARK: - 主操作（发送码 or 登录）
    private func primaryAction() async {
        guard agreedToTerms else {
            await MainActor.run { triggerAgreementToast(for: 2.5) }
            return
        }
        if showCodeInput {
            await performLogin()
        } else {
            await sendCode()
        }
    }

    // MARK: - Toast 显隐控制
    @MainActor
    private func triggerAgreementToast(for duration: TimeInterval) {
        withAnimation { isShowingAgreementToast = true }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run { withAnimation { isShowingAgreementToast = false } }
        }
    }

    // MARK: - 发送验证码
    private func sendCode() async {
        guard isValidPhone else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            // ⚠️ 后端未上线时会 throw 网络错误，DEBUG 下走 fallback
            #if DEBUG
            // 模拟发送成功
            try await Task.sleep(nanoseconds: 800_000_000)
            #else
            try await AuthService.sendCode(phone: phoneNumber)
            #endif

            await MainActor.run {
                showCodeInput = true
                startCountdown()
            }
        } catch {
            #if DEBUG
            // DEBUG 模式降级：仍然展示验证码输入框
            await MainActor.run {
                showCodeInput = true
                startCountdown()
                errorMessage = "【调试模式】验证码已发送（使用 123456 登录）"
                showError = true
            }
            #else
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
            #endif
        }
    }

    // MARK: - 执行登录
    private func performLogin() async {
        guard verificationCode.count == 6 else {
            errorMessage = "请输入6位验证码"
            showError = true
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            #if DEBUG
            // 调试模式：接受任意6位数字，生成假 Token
            try await Task.sleep(nanoseconds: 600_000_000)
            let fakeToken = "debug_token_\(UUID().uuidString)"
            let expiry = Calendar.current.date(byAdding: .day, value: 90, to: Date())
            await MainActor.run {
                appState.saveSession(token: fakeToken, phone: phoneNumber, expiresAt: expiry)
            }
            #else
            let response = try await AuthService.login(phone: phoneNumber, code: verificationCode)
            await MainActor.run {
                appState.saveSession(
                    token: response.token,
                    phone: phoneNumber,
                    expiresAt: response.expiryDate
                )
            }
            #endif
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - 倒计时
    private func startCountdown() {
        countdown = 60
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if countdown > 0 {
                countdown -= 1
            } else {
                timer.invalidate()
            }
        }
    }
}

// MARK: - 收起键盘工具函数
func hideKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil, from: nil, for: nil
    )
}

// MARK: - Preview
#Preview {
    LoginView()
        .environmentObject(AppState())
}
