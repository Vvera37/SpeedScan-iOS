//
//  CameraView.swift
//  SpeedScan
//
//  拍图识字：DataScannerViewController（实时文字扫描）
//  拍PPT：  VNDocumentCameraViewController（自动校正歪斜+颜色，多页连拍）
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
        ZStack {
            Color.black.ignoresSafeArea()
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
        }
    }
}

// MARK: - DataScanner 封装（拍图识字）
struct DataScannerRepresentable: UIViewControllerRepresentable {
    var onVCReady: (DataScannerViewController) -> Void
    var onTextRecognized: (String) -> Void   // 实时识别回调

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighlightingEnabled: true   // 识别到的文字显示高亮框
        )
        scanner.delegate = context.coordinator
        context.coordinator.onVCReady    = onVCReady
        context.coordinator.onTextRecognized = onTextRecognized
        return scanner
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        guard !vc.isScanning else { return }
        do {
            try vc.startScanning()
            context.coordinator.onVCReady?(vc)
            context.coordinator.onVCReady = nil
        } catch {
            print("❌ startScanning 失败：\(error)")
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onVCReady: ((DataScannerViewController) -> Void)?
        var onTextRecognized: ((String) -> Void)?

        // 实时识别到文字时触发
        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .text(let text) = item {
                    onTextRecognized?(text.transcript)
                }
            }
        }
    }
}

// MARK: - VNDocumentCamera 封装（拍PPT，自动校正）
struct DocumentCameraRepresentable: UIViewControllerRepresentable {
    var onScanned: ([UIImage]) -> Void
    var onDismiss: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onScanned: onScanned, onDismiss: onDismiss) }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScanned: ([UIImage]) -> Void
        let onDismiss: () -> Void
        init(onScanned: @escaping ([UIImage]) -> Void, onDismiss: @escaping () -> Void) {
            self.onScanned = onScanned; self.onDismiss = onDismiss
        }
        func documentCameraViewController(_ vc: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount { images.append(scan.imageOfPage(at: i)) }
            onScanned(images)
        }
        func documentCameraViewControllerDidCancel(_ vc: VNDocumentCameraViewController) { onDismiss() }
        func documentCameraViewController(_ vc: VNDocumentCameraViewController, didFailWithError error: Error) {
            print("❌ VNDocumentCamera 失败：\(error)"); onDismiss()
        }
    }
}

// MARK: - CameraView 主视图
struct CameraView: View {
    @Binding var capturedImage: UIImage?
    var onDismiss: () -> Void
    var onPPTDone: (([UIImage]) -> Void)?

    @State private var scannerVC: DataScannerViewController? = nil
    @State private var selectedMode: CaptureMode = .scan
    @State private var cameraPermissionDenied = false
    @State private var showAlbumPicker = false
    @State private var isCapturing = false

    // PPT 连拍堆栈
    @State private var pptBuffer: [UIImage] = []
    // 是否显示 VNDocumentCamera（拍PPT）
    @State private var showDocumentCamera = false

    // 实时识别到的文字（调试展示）
    @State private var liveText = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if showDocumentCamera {
                // 拍PPT：VNDocumentCameraViewController 全屏
                DocumentCameraRepresentable(
                    onScanned: { images in
                        pptBuffer.append(contentsOf: images)
                        showDocumentCamera = false
                    },
                    onDismiss: {
                        showDocumentCamera = false
                        if pptBuffer.isEmpty { dismissSafely() }
                    }
                )
                .ignoresSafeArea()
            } else {
                VStack(spacing: 0) {
                    topToolbar
                    cameraArea
                    bottomArea
                }
            }

            // PPT 堆栈缩略图（右下角，无感连拍）
            if !pptBuffer.isEmpty && !showDocumentCamera {
                pptStackOverlay
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

    // MARK: 拍图识字 - 快门
    private func capturePhoto() {
        guard !isCapturing, let vc = scannerVC else {
            print("❌ scannerVC nil 或正在拍照中"); return
        }
        isCapturing = true
        Task {
            do {
                let image = try await vc.capturePhoto()
                await MainActor.run {
                    isCapturing = false
                    capturedImage = image
                    dismissSafely()
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
                    .foregroundColor(.white).frame(width: 44, height: 44)
            }
            Spacer()
            if selectedMode == .ppt && !pptBuffer.isEmpty {
                Button {
                    // 完成 - 传回所有页
                    onPPTDone?(pptBuffer)
                    dismissSafely()
                } label: {
                    Text("完成 (\(pptBuffer.count)页)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.themeGreen).cornerRadius(16)
                }
            }
            Spacer()
            Button { showAlbumPicker = true } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 22)).foregroundColor(.white).frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 20).padding(.top, 8).background(Color.black)
    }

    // MARK: 取景区
    @ViewBuilder
    private var cameraArea: some View {
        Group {
            if cameraPermissionDenied {
                CameraPermissionView()
            } else if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                DataScannerRepresentable(
                    onVCReady: { vc in scannerVC = vc },
                    onTextRecognized: { text in
                        // 拍图识字模式下实时更新（可用于未来实时展示）
                        if selectedMode == .scan { liveText = text }
                    }
                )
                .ignoresSafeArea(edges: [])
            } else {
                ZStack {
                    Color.black
                    Text("需要 iOS 16 或以上版本").foregroundColor(.white)
                }
            }
        }
        .frame(maxWidth: .infinity).layoutPriority(1)
    }

    // MARK: 底部区域
    @ViewBuilder
    private var bottomArea: some View {
        VStack(spacing: 0) {
            if selectedMode == .ppt {
                Text(pptBuffer.isEmpty ? "点击快门，开始扫描 PPT" : "继续扫描下一张，或点击右上角完成")
                    .font(.system(size: 13)).foregroundColor(Color(white: 0.65))
                    .padding(.top, 12)
            }

            ShutterButton {
                if selectedMode == .ppt {
                    showDocumentCamera = true  // 调起 VNDocumentCamera
                } else {
                    capturePhoto()
                }
            }
            .padding(.top, 16).padding(.bottom, 16)

            // 模式 Tab
            HStack(spacing: 40) {
                ForEach(CaptureMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedMode = mode
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
            }.padding(.bottom, 8)

            Color.clear.frame(height: 16)
                .sheet(isPresented: $showAlbumPicker) {
                    ImagePicker(sourceType: .photoLibrary, selectedImage: $capturedImage)
                        .onDisappear { if capturedImage != nil { dismissSafely() } }
                }
        }
        .background(Color.black)
    }

    // MARK: PPT 堆栈缩略图（右下角飞入效果）
    @ViewBuilder
    private var pptStackOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ZStack {
                    // 最多叠显示 3 张
                    ForEach(Array(pptBuffer.suffix(3).enumerated()), id: \.offset) { idx, img in
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 56, height: 72).clipped()
                            .cornerRadius(6)
                            .shadow(radius: 4)
                            .offset(x: CGFloat(idx - 1) * 4, y: CGFloat(idx - 1) * (-4))
                    }
                    // 页数角标
                    Text("\(pptBuffer.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.themeGreen)
                        .clipShape(Circle())
                        .offset(x: 22, y: -30)
                }
                .padding(.trailing, 20).padding(.bottom, 20)
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.3), value: pptBuffer.count)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    CameraView(capturedImage: .constant(nil), onDismiss: {})
}
