//
//  CameraView.swift
//  SpeedScan
//
//  自定义相机页面 — 多模式 Tab / 快门 / 证件 Overlay / AVFoundation
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - 颜色常量（init(hex:) 复用 ScanView.swift 里的定义，同模块共享）
fileprivate extension Color {
    static let themeGreen  = Color(hex: "#34C759")
    static let capsuleBg   = Color(white: 0.22)
    static let tabInactive = Color(white: 0.5)
}

// MARK: - 拍摄模式枚举
enum CaptureMode: String, CaseIterable, Identifiable {
    case scan       = "扫描"
    case ppt        = "拍PPT"
    case toWord     = "拍图转Word"
    case extractText = "提取文字"
    case idCard     = "扫描证件"

    var id: String { rawValue }

    /// 说明标题（nil 表示不显示说明区）
    var descTitle: String? {
        switch self {
        case .ppt:      return "PPT 拍摄利器"
        case .toWord:   return "图片转 Word"
        default:        return nil
        }
    }

    /// 说明副文本
    var descSubtitle: String? {
        switch self {
        case .ppt:    return "会议或课堂，一键抓拍屏幕与板书，高清易读，摆脱屏幕纹理"
        case .toWord: return "自动识别文字并还原文档格式"
        default:      return nil
        }
    }

    /// 是否显示单页/多页胶囊
    var showPageCapsule: Bool {
        switch self {
        case .scan, .extractText: return true
        default: return false
        }
    }

    /// 是否显示绿色扫描线
    var showScanLine: Bool { self == .ppt }

    /// 是否显示证件 Overlay
    var showIdCardOverlay: Bool { self == .idCard }

    /// 是否显示"关于提取文字"标签
    var showExtractTextTag: Bool { self == .extractText }
}

// MARK: - 相机预览（UIViewControllerRepresentable）
struct CameraPreviewView: UIViewControllerRepresentable {
    @Binding var flashMode: AVCaptureDevice.FlashMode
    var onCapture: (UIImage) -> Void
    weak var controller: CameraViewController?

    class Coordinator: NSObject {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onCapture = onCapture
        return vc
    }

    func updateUIViewController(_ vc: CameraViewController, context: Context) {
        vc.flashMode = flashMode
    }
}

// MARK: - CameraViewController（AVFoundation 核心）
class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {

    var onCapture: ((UIImage) -> Void)?
    var flashMode: AVCaptureDevice.FlashMode = .off

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var currentDevice: AVCaptureDevice?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    /// 显式停止 session，释放相机资源。
    /// SwiftUI dismiss 时由 CameraView.onDismiss 主动调用，防止 OOM。
    func stopSession() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupSession() {
        // 必须先在主线程检查权限状态，再切到后台配置
        // 严禁在主线程调用 configureSession — AVCaptureDeviceInput 初始化会触发 mach_msg2_trap 死锁
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .authorized || status == .notDetermined else { return }

        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                // requestAccess 回调已在后台线程，可直接配置
                self?.configureSession()
            }
        } else {
            // 切到后台线程，避免主线程 mach_msg2_trap
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.configureSession()
            }
        }
    }

    private func configureSession() {
        // ⚠️ 此函数必须在后台线程调用
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }

        currentDevice = device

        if session.canAddInput(input) {
            session.addInput(input)
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()

        // 预览层必须回主线程添加（UI 操作）
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
            self.previewLayer.videoGravity = .resizeAspectFill
            self.previewLayer.frame = self.view.bounds
            self.view.layer.insertSublayer(self.previewLayer, at: 0)
        }

        // startRunning 在后台执行（已在后台线程，直接调用）
        session.startRunning()
    }

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        if let device = currentDevice, device.hasFlash {
            settings.flashMode = flashMode
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        onCapture?(image)
    }
}

// MARK: - 证件 Overlay
struct IdCardOverlayView: View {
    @Binding var selectedIdType: String

    let idTypes = ["全部类型", "通用证件", "身份证", "户口本"]

    var body: some View {
        VStack(spacing: 0) {
            // 白色卡片
            VStack(spacing: 12) {
                // 顶部标签
                Text("A4 纸示例")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(white: 0.92))
                    .cornerRadius(6)

                // 占位图
                Image(systemName: "person.text.rectangle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 80)
                    .foregroundColor(Color(white: 0.75))

                // 底部安全提示
                Text("🛡 扫描鸡保护你的证件信息安全")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .cornerRadius(16)
            .padding(.horizontal, 24)

            // 卡片下方说明文字
            Text("请将证件放在取景框内，保持平整")
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.65))
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 24)

            // 子选项胶囊
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(idTypes, id: \.self) { type in
                        Button {
                            selectedIdType = type
                        } label: {
                            Text(type)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(selectedIdType == type ? .black : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(selectedIdType == type ? Color.white : Color(white: 0.28))
                                .cornerRadius(20)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 10)

            // 立即制作按钮（暂触发普通拍照，功能后续迭代）
            // 此按钮需要外部注入 action，通过 onMakeAction 回调
        }
    }
}

// MARK: - 扫描线动画
struct ScanLineView: View {
    @State private var offsetY: CGFloat = 0
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.themeGreen.opacity(0.85))
                .frame(height: 2)
                .shadow(color: Color.themeGreen.opacity(0.6), radius: 6, x: 0, y: 0)
                .offset(y: offsetY)
                .onAppear {
                    withAnimation(
                        .linear(duration: 2.2).repeatForever(autoreverses: false)
                    ) {
                        offsetY = geo.size.height - 2
                    }
                }
        }
        .frame(height: height)
        .clipped()
    }
}

// MARK: - 单页/多页胶囊
struct PageModeCapsule: View {
    @Binding var isMultiPage: Bool

    var body: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isMultiPage = false }
            } label: {
                Text("单页")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isMultiPage ? Color(white: 0.6) : .black)
                    .frame(width: 60, height: 32)
                    .background(isMultiPage ? Color.clear : Color.white)
                    .cornerRadius(16)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isMultiPage = true }
            } label: {
                Text("多页")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isMultiPage ? .black : Color(white: 0.6))
                    .frame(width: 60, height: 32)
                    .background(isMultiPage ? Color.white : Color.clear)
                    .cornerRadius(16)
            }
        }
        .padding(2)
        .background(Color(white: 0.22))
        .cornerRadius(18)
    }
}

// MARK: - 快门按钮
struct ShutterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.themeGreen, lineWidth: 3)
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(Color.white)
                    .frame(width: 60, height: 60)
            }
        }
        .buttonStyle(ScaleButtonStyle2())
    }
}

private struct ScaleButtonStyle2: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - 相机权限提示
struct CameraPermissionView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("请在设置中开启相机权限")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
            Button("前往设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.themeGreen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// MARK: - CameraView 主视图
struct CameraView: View {
    @Binding var capturedImage: UIImage?
    var onDismiss: () -> Void

    // 相机控制器引用（通过闭包传递）
    @State private var cameraVC: CameraViewController? = nil

    // 状态
    @State private var selectedMode: CaptureMode = .scan
    @State private var flashMode: AVCaptureDevice.FlashMode = .off
    @State private var isMultiPage: Bool = false
    @State private var selectedIdType: String = "全部类型"
    @State private var cameraPermissionDenied: Bool = false
    @State private var showAlbumPicker = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── 1. 顶部工具栏 ──────────────────────────────────────
                topToolbar

                // ── 2. 相机取景区 ──────────────────────────────────────
                cameraArea

                // ── 3. 模式说明区 ──────────────────────────────────────
                if let title = selectedMode.descTitle {
                    modeDescView(title: title, subtitle: selectedMode.descSubtitle)
                }

                // ── 4. 单页/多页胶囊 ────────────────────────────────────
                if selectedMode.showPageCapsule {
                    PageModeCapsule(isMultiPage: $isMultiPage)
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                }

                // ── 5. 底部区域：快门 + Tab + 辅助图标 ─────────────────
                bottomArea
            }
        }
        .onAppear {
            checkCameraPermission()
        }
    }

    // MARK: 权限检查
    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted {
            cameraPermissionDenied = true
        }
    }

    // MARK: 安全关闭（主动释放相机资源，防止 OOM SIGTERM）
    private func dismissSafely() {
        cameraVC?.stopSession()
        onDismiss()
    }

    // MARK: 顶部工具栏
    @ViewBuilder
    private var topToolbar: some View {
        HStack {
            // 关闭
            Button { dismissSafely() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            // 闪光灯
            Button {
                flashMode = (flashMode == .off) ? .on : .off
            } label: {
                Image(systemName: flashMode == .off ? "bolt.slash.fill" : "bolt.fill")
                    .font(.system(size: 20))
                    .foregroundColor(flashMode == .on ? Color(hex: "#FFD60A") : .white)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            // HD 标签
            ZStack(alignment: .topTrailing) {
                Text("HD")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(white: 0.3))
                    .cornerRadius(8)

                Circle()
                    .fill(Color.themeGreen)
                    .frame(width: 8, height: 8)
                    .offset(x: 4, y: -4)
            }
            .frame(width: 44, height: 44)

            Spacer()

            // 相册入口（右上角）
            Button {
                showAlbumPicker = true
            } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .background(Color.black)
    }

    // MARK: 相机取景区
    @ViewBuilder
    private var cameraArea: some View {
        GeometryReader { geo in
            ZStack {
                if cameraPermissionDenied {
                    CameraPermissionView()
                } else {
                    // AVFoundation 预览
                    CameraPreviewRepresentable(onVCReady: { vc in
                        cameraVC = vc
                        vc.onCapture = { img in
                            capturedImage = img
                            dismissSafely()
                        }
                        vc.flashMode = flashMode
                    })
                    .ignoresSafeArea(edges: [])
                    .allowsHitTesting(false)
                    .onChange(of: flashMode) { _, newMode in
                        cameraVC?.flashMode = newMode
                    }
                }

                // 扫描线（拍PPT模式）
                if selectedMode.showScanLine {
                    ScanLineView(height: geo.size.height)
                }

                // 证件 Overlay
                if selectedMode.showIdCardOverlay {
                    VStack {
                        IdCardOverlayWithAction(
                            selectedIdType: $selectedIdType,
                            onCapture: { cameraVC?.capturePhoto() }
                        )
                        .padding(.top, 24)
                        Spacer()
                    }
                }

                // 提取文字 — 右上角标签
                if selectedMode.showExtractTextTag {
                    VStack {
                        HStack {
                            Spacer()
                            Text("关于提取文字")
                                .font(.system(size: 12))
                                .foregroundColor(Color(white: 0.65))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(white: 0.2))
                                .cornerRadius(8)
                                .padding(.trailing, 16)
                                .padding(.top, 12)
                        }
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 模式说明区
    @ViewBuilder
    private func modeDescView(title: String, subtitle: String?) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    // MARK: 底部区域
    @ViewBuilder
    private var bottomArea: some View {
        VStack(spacing: 0) {
            // 快门
            ShutterButton {
                cameraVC?.capturePhoto()
            }
            .padding(.top, 20)
            .padding(.bottom, 16)
            .zIndex(10) // 确保快门在最顶层，不被取景区遮挡

            // 模式 Tab 栏
            modeTabBar

            // 辅助图标区
            auxIconsRow
        }
        .background(Color.black)
        .zIndex(10)
    }

    // MARK: 模式 Tab 栏
    @ViewBuilder
    private var modeTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 28) {
                ForEach(CaptureMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedMode = mode
                        }
                    } label: {
                        VStack(spacing: 5) {
                            // 选中圆点
                            Circle()
                                .fill(selectedMode == mode ? Color.themeGreen : Color.clear)
                                .frame(width: 6, height: 6)

                            Text(mode.rawValue)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(selectedMode == mode ? Color.themeGreen : Color.tabInactive)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 44)
    }

    // MARK: 辅助图标区（底部，相册已移至右上角工具栏）
    @ViewBuilder
    private var auxIconsRow: some View {
        Color.clear
            .frame(height: 20)
            .sheet(isPresented: $showAlbumPicker) {
                ImagePicker(sourceType: .photoLibrary, selectedImage: $capturedImage)
                    .onDisappear {
                        if capturedImage != nil { dismissSafely() }
                    }
            }
    }
}

// MARK: - 证件 Overlay（含「立即制作」按钮）
struct IdCardOverlayWithAction: View {
    @Binding var selectedIdType: String
    var onCapture: () -> Void

    let idTypes = ["全部类型", "通用证件", "身份证", "户口本"]

    var body: some View {
        VStack(spacing: 12) {
            // 白色卡片
            VStack(spacing: 12) {
                Text("A4 纸示例")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(white: 0.92))
                    .cornerRadius(6)

                Image(systemName: "person.text.rectangle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 80)
                    .foregroundColor(Color(white: 0.75))

                Text("🛡 扫描鸡保护你的证件信息安全")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .cornerRadius(16)
            .padding(.horizontal, 24)

            // 说明
            Text("请将证件放在取景框内，保持平整")
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // 子选项胶囊
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(idTypes, id: \.self) { type in
                        Button {
                            selectedIdType = type
                        } label: {
                            Text(type)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(selectedIdType == type ? .black : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(selectedIdType == type ? Color.white : Color(white: 0.28))
                                .cornerRadius(20)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            // 立即制作
            Button(action: onCapture) {
                Text("立即制作")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.themeGreen)
                    .cornerRadius(26)
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - 相机预览桥接（获取 VC 引用）
struct CameraPreviewRepresentable: UIViewControllerRepresentable {
    var onVCReady: (CameraViewController) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        onVCReady(vc)
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

// MARK: - Preview
#Preview {
    CameraView(
        capturedImage: .constant(nil),
        onDismiss: {}
    )
}
