//
//  CameraView.swift
//  SpeedScan
//
//  相机页面 — 基于 DataScannerViewController（iOS 16+ 苹果官方方案）
//  替换原 AVCaptureSession 手动封装，彻底解决快门失效问题
//

import SwiftUI
import VisionKit
import AVFoundation

// MARK: - 颜色常量
fileprivate extension Color {
    static let themeGreen  = Color(hex: "#34C759")
    static let capsuleBg   = Color(white: 0.22)
    static let tabInactive = Color(white: 0.5)
}

// MARK: - 拍摄模式枚举
enum CaptureMode: String, CaseIterable, Identifiable {
    case scan        = "扫描"
    case ppt         = "拍PPT"
    case toWord      = "拍图转Word"
    case extractText = "提取文字"
    case idCard      = "扫描证件"

    var id: String { rawValue }

    var descTitle: String? {
        switch self {
        case .ppt:    return "PPT 拍摄利器"
        case .toWord: return "图片转 Word"
        default:      return nil
        }
    }

    var descSubtitle: String? {
        switch self {
        case .ppt:    return "会议或课堂，一键抓拍屏幕与板书，高清易读，摆脱屏幕纹理"
        case .toWord: return "自动识别文字并还原文档格式"
        default:      return nil
        }
    }

    var showPageCapsule: Bool {
        switch self {
        case .scan, .extractText: return true
        default: return false
        }
    }
}

// MARK: - DataScanner 封装（UIViewControllerRepresentable）
struct DataScannerRepresentable: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    var onVCReady: (DataScannerViewController) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        context.coordinator.onCapture = onCapture
        print("✅ DataScanner 控制器已就绪")
        onVCReady(scanner)
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCapture: ((UIImage) -> Void)?

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didTapOn item: RecognizedItem) {}
    }
}

// MARK: - 单页/多页胶囊
struct PageModeCapsule: View {
    @Binding var isMultiPage: Bool

    var body: some View {
        HStack(spacing: 0) {
            capsuleBtn(label: "单页", active: !isMultiPage) {
                withAnimation(.easeInOut(duration: 0.18)) { isMultiPage = false }
            }
            capsuleBtn(label: "多页", active: isMultiPage) {
                withAnimation(.easeInOut(duration: 0.18)) { isMultiPage = true }
            }
        }
        .padding(2)
        .background(Color(white: 0.22))
        .cornerRadius(18)
    }

    @ViewBuilder
    private func capsuleBtn(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(active ? .black : Color(white: 0.6))
                .frame(width: 60, height: 32)
                .background(active ? Color.white : Color.clear)
                .cornerRadius(16)
        }
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

    @State private var scannerVC: DataScannerViewController? = nil
    @State private var selectedMode: CaptureMode = .scan
    @State private var flashMode: AVCaptureDevice.FlashMode = .off
    @State private var isMultiPage: Bool = false
    @State private var selectedIdType: String = "全部类型"
    @State private var cameraPermissionDenied: Bool = false
    @State private var showAlbumPicker = false
    @State private var isCapturing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topToolbar
                cameraArea
                if let title = selectedMode.descTitle {
                    modeDescView(title: title, subtitle: selectedMode.descSubtitle)
                }
                if selectedMode.showPageCapsule {
                    PageModeCapsule(isMultiPage: $isMultiPage)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                }
                bottomArea
            }
        }
        .onAppear { checkCameraPermission() }
    }

    // MARK: 权限检查
    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted {
            cameraPermissionDenied = true
        }
    }

    private func dismissSafely() {
        scannerVC?.stopScanning()
        onDismiss()
    }

    // MARK: 拍照（截取当前帧）
    private func captureCurrentFrame() {
        guard !isCapturing else { return }
        isCapturing = true
        print("📸 快门触发，scannerVC = \(String(describing: scannerVC))")

        guard let vc = scannerVC else {
            print("❌ scannerVC 为 nil，无法拍照")
            isCapturing = false
            return
        }

        // 截取 DataScanner 预览层当前帧
        let renderer = UIGraphicsImageRenderer(bounds: vc.view.bounds)
        let image = renderer.image { ctx in
            vc.view.layer.render(in: ctx.cgContext)
        }
        capturedImage = image
        isCapturing = false
        dismissSafely()
    }

    // MARK: 顶部工具栏
    @ViewBuilder
    private var topToolbar: some View {
        HStack {
            Button { dismissSafely() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Button {
                flashMode = (flashMode == .off) ? .on : .off
                if flashMode == .on {
                    try? scannerVC?.capturePhoto() // 闪光灯通过系统处理
                }
            } label: {
                Image(systemName: flashMode == .off ? "bolt.slash.fill" : "bolt.fill")
                    .font(.system(size: 20))
                    .foregroundColor(flashMode == .on ? Color(hex: "#FFD60A") : .white)
                    .frame(width: 44, height: 44)
            }
            Spacer()
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
            Button { showAlbumPicker = true } label: {
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

    // MARK: 取景区
    @ViewBuilder
    private var cameraArea: some View {
        Group {
            if cameraPermissionDenied {
                CameraPermissionView()
            } else if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                DataScannerRepresentable(
                    onCapture: { img in
                        capturedImage = img
                        dismissSafely()
                    },
                    onVCReady: { vc in
                        scannerVC = vc
                        try? vc.startScanning()
                    }
                )
                .ignoresSafeArea(edges: [])
            } else {
                // 降级：设备不支持 DataScanner（iOS < 16 或模拟器）
                ZStack {
                    Color.black
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("需要 iOS 16 或以上版本")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .layoutPriority(1)
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
            ShutterButton {
                captureCurrentFrame()
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            modeTabBar
            auxIconsRow
        }
        .background(Color.black)
    }

    // MARK: 模式 Tab 栏
    @ViewBuilder
    private var modeTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 28) {
                ForEach(CaptureMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selectedMode = mode }
                    } label: {
                        VStack(spacing: 5) {
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

    // MARK: 辅助图标区
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

// MARK: - Preview
#Preview {
    CameraView(capturedImage: .constant(nil), onDismiss: {})
}
