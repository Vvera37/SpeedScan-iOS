//
//  CameraView.swift
//  SpeedScan
//
//  相机页面 — 基于 DataScannerViewController（iOS 16+）
//  模式：拍图识字 / 拍PPT（多页）
//

import SwiftUI
import VisionKit
import AVFoundation

// MARK: - 颜色常量
fileprivate extension Color {
    static let themeGreen  = Color(hex: "#34C759")
    static let tabInactive = Color(white: 0.5)
}

// MARK: - 拍摄模式
enum CaptureMode: String, CaseIterable, Identifiable {
    case scan = "拍图识字"
    case ppt  = "拍PPT"
    var id: String { rawValue }
}

// MARK: - DataScanner 封装
struct DataScannerRepresentable: UIViewControllerRepresentable {
    var onVCReady: (DataScannerViewController) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighlightingEnabled: false
        )
        print("✅ DataScanner 已就绪")
        DispatchQueue.main.async { onVCReady(scanner) }
        return scanner
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator: NSObject, DataScannerViewControllerDelegate {}
}

// MARK: - 快门按钮
struct ShutterButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(Color.themeGreen, lineWidth: 3).frame(width: 80, height: 80)
                Circle().fill(Color.white).frame(width: 60, height: 60)
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

// MARK: - 权限提示
struct CameraPermissionView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.system(size: 48)).foregroundColor(.gray)
            Text("请在设置中开启相机权限").font(.system(size: 17, weight: .medium)).foregroundColor(.white)
            Button("前往设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 15, weight: .medium)).foregroundColor(.themeGreen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
    }
}

// MARK: - CameraView
struct CameraView: View {
    @Binding var capturedImage: UIImage?
    var onDismiss: () -> Void

    // PPT 多页模式：外部传入已有页面，拍完追加
    var pptPages: Binding<[UIImage]>?
    var onPPTDone: (([UIImage]) -> Void)?

    @State private var scannerVC: DataScannerViewController? = nil
    @State private var selectedMode: CaptureMode = .scan
    @State private var cameraPermissionDenied = false
    @State private var showAlbumPicker = false
    @State private var isCapturing = false

    // PPT 多页临时存储
    @State private var pptBuffer: [UIImage] = []
    @State private var showPPTActions = false
    @State private var lastCaptured: UIImage? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topToolbar
                cameraArea
                bottomArea
            }

            // PPT 拍完一张后的操作浮层
            if showPPTActions, let last = lastCaptured {
                PPTActionOverlay(
                    lastImage: last,
                    pageCount: pptBuffer.count,
                    onContinue: {
                        showPPTActions = false
                        _ = try? scannerVC?.startScanning()
                    },
                    onDone: {
                        showPPTActions = false
                        onPPTDone?(pptBuffer)
                        dismissSafely()
                    }
                )
            }
        }
        .onAppear { checkCameraPermission() }
    }

    // MARK: 权限检查
    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraPermissionDenied = (status == .denied || status == .restricted)
    }

    private func dismissSafely() {
        scannerVC?.stopScanning()
        onDismiss()
    }

    // MARK: 拍照
    private func capturePhoto() {
        guard !isCapturing, let vc = scannerVC else {
            print("❌ scannerVC nil 或正在拍照中")
            return
        }
        isCapturing = true
        print("📸 快门触发")

        Task {
            do {
                let image = try await vc.capturePhoto()
                await MainActor.run {
                    isCapturing = false
                    if selectedMode == .ppt {
                        pptBuffer.append(image)
                        lastCaptured = image
                        vc.stopScanning()
                        showPPTActions = true
                    } else {
                        capturedImage = image
                        dismissSafely()
                    }
                }
            } catch {
                print("❌ capturePhoto 失败：\(error)")
                await MainActor.run { isCapturing = false }
            }
        }
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
            // PPT 模式显示已拍页数
            if selectedMode == .ppt && !pptBuffer.isEmpty {
                Text("\(pptBuffer.count) 页")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.themeGreen.opacity(0.8))
                    .cornerRadius(12)
            }
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
                DataScannerRepresentable(onVCReady: { vc in
                    scannerVC = vc
                    _ = try? vc.startScanning()
                })
                .ignoresSafeArea(edges: [])
            } else {
                ZStack {
                    Color.black
                    Text("需要 iOS 16 或以上版本").foregroundColor(.white)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .layoutPriority(1)
    }

    // MARK: 底部区域
    @ViewBuilder
    private var bottomArea: some View {
        VStack(spacing: 0) {
            // PPT 模式提示
            if selectedMode == .ppt {
                Text("对准 PPT 页面，点击快门拍摄")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.65))
                    .padding(.top, 12)
            }

            ShutterButton { capturePhoto() }
                .padding(.top, 16)
                .padding(.bottom, 16)

            // 模式 Tab
            HStack(spacing: 40) {
                ForEach(CaptureMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedMode = mode
                            // 切换模式时清空 PPT buffer
                            if mode != .ppt { pptBuffer = [] }
                        }
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
            .padding(.bottom, 8)

            // 相册 sheet
            Color.clear.frame(height: 16)
                .sheet(isPresented: $showAlbumPicker) {
                    ImagePicker(sourceType: .photoLibrary, selectedImage: $capturedImage)
                        .onDisappear { if capturedImage != nil { dismissSafely() } }
                }
        }
        .background(Color.black)
    }
}

// MARK: - PPT 拍完一张后的操作浮层
struct PPTActionOverlay: View {
    let lastImage: UIImage
    let pageCount: Int
    let onContinue: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()

                // 缩略图预览
                Image(uiImage: lastImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .cornerRadius(12)
                    .padding(.horizontal, 24)

                Text("第 \(pageCount) 页已拍摄")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(white: 0.8))
                    .padding(.top, 16)

                // 操作按钮
                HStack(spacing: 16) {
                    Button(action: onContinue) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("继续拍PPT")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(white: 0.25))
                        .cornerRadius(14)
                    }

                    Button(action: onDone) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                            Text("完成保存")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.themeGreen)
                        .cornerRadius(14)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    CameraView(capturedImage: .constant(nil), onDismiss: {})
}
