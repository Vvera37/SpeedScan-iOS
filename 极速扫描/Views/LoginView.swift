//
// 登录界面 - 手机号免密登录
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var phoneNumber: String = ""
    @State private var verificationCode: String = ""
    @State private var isSendingCode = false
    @State private var countdown = 0
    @State private var showCodeInput = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Logo区域
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text(LocalizedStringKey("app_name"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("更快、更准确、更便宜")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 60)
                
                // 输入区域
                VStack(spacing: 20) {
                    // 手机号输入
                    HStack {
                        Text("+86")
                            .foregroundColor(.secondary)
                            .padding(.leading, 12)
                        
                        TextField("请输入手机号", text: $phoneNumber)
                            .keyboardType(.numberPad)
                            .textContentType(.telephoneNumber)
                            .onChange(of: phoneNumber) { newValue in
                                // 限制11位
                                if newValue.count > 11 {
                                    phoneNumber = String(newValue.prefix(11))
                                }
                                // 只允许数字
                                phoneNumber = newValue.filter { $0.isNumber }
                            }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // 验证码输入（发送后显示）
                    if showCodeInput {
                        HStack {
                            TextField("请输入验证码", text: $verificationCode)
                                .keyboardType(.numberPad)
                            
                            Button(action: sendVerificationCode) {
                                Text(countdown > 0 ? "\(countdown)s" : "重新发送")
                                    .foregroundColor(countdown > 0 ? .gray : .blue)
                            }
                            .disabled(countdown > 0 || isSendingCode)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                
                // 登录按钮
                Button(action: performLogin) {
                    HStack {
                        if isSendingCode {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(showCodeInput ? LocalizedStringKey("btn_login") : LocalizedStringKey("btn_send_code"))
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValidPhone ? Color.blue : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(!isValidPhone || isSendingCode)
                .padding(.horizontal)
                
                Spacer()
                
                // 隐私提示
                Text("登录即表示同意《用户协议》和《隐私政策》")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 20)
            }
            .padding()
            .navigationBarHidden(true)
        }
    }
    
    // MARK: - 验证手机号格式
    private var isValidPhone: Bool {
        let regex = "^1[3-9]\\d{9}$"
        return phoneNumber.range(of: regex, options: .regularExpression) != nil
    }
    
    // MARK: - 发送验证码
    private func sendVerificationCode() {
        isSendingCode = true
        
        // 模拟发送验证码
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isSendingCode = false
            showCodeInput = true
            startCountdown()
            
            // 实际应调用短信API
            print("验证码已发送至: \(phoneNumber)")
        }
    }
    
    // MARK: - 开始倒计时
    private func startCountdown() {
        countdown = 60
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if countdown > 0 {
                countdown -= 1
            } else {
                timer.invalidate()
            }
        }
    }
    
    // MARK: - 执行登录
    private func performLogin() {
        if !showCodeInput {
            sendVerificationCode()
            return
        }
        
        // 验证验证码（实际应调用后端API）
        guard verificationCode.count == 6 else { return }
        
        // 登录成功
        appState.isLoggedIn = true
        // 设置90天有效期
        appState.sessionExpiry = Calendar.current.date(byAdding: .day, value: 90, to: Date())
        
        // 保存登录状态到本地
        UserDefaults.standard.set(phoneNumber, forKey: "user_phone")
        UserDefaults.standard.set(appState.sessionExpiry, forKey: "session_expiry")
    }
}
