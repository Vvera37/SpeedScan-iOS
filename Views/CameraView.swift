//
//  CameraView.swift
//  SpeedScan
//
//  拍图识字：DataScannerViewController（实时文字扫描）
//  拍PPT：  引导页 → VNDocumentCamera / PHPicker(UIKit present) → 预览管理 → 转化进度 → 分享
//

import SwiftUI
import VisionKit
import AVFoundation
import PhotosUI

// MARK: - 颜色常量
fileprivate extension Color {
    static let themeGreen  = Color(hex: "#34C759")
    static let themeBlue   = Color(hex: "#007AFF")
    static let tabInactive = Color(white: 0.5)
}

// MARK: - 拍摄模式
enum CaptureMode: String, CaseIterable, Identifiable {
    case scan = "拍图识字"
    case ppt  = "拍PPT"
    var id: String { rawValue }
}

// MARK: - PPT 页面状态
enum PPTFlowState {
    case guide
    case preview
    case converting
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
    var onTextRecognized: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        context.coordinator.onVCReady       = onVCReady
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

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .text(let text) = item { onTextRecognized?(text.transcript) }
            }
        }
    }
}

// MARK: - VNDocumentCamera 封装（拍PPT）
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
        func documentCameraViewController(_ vc: VNDocumentCameraViewController,
                                          didFailWithError error: Error) { onDismiss() }
    }
}

// MARK: - Toast
struct ToastView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.78))
            .cornerRadius(24)
    }
}

// MARK: - PHPicker UIKit present 封装
// 用 UIKit 直接 present，绕开 SwiftUI 嵌套 modal 导致外层 fullScreenCover 被连带 dismiss 的 bug
func presentPHPicker(onSelected: @escaping ([UIImage]) -> Void, onDismiss: @escaping () -> Void) {
    var config = PHPickerConfiguration(photoLibrary: .shared())
    config.filter         = .images
    config.selectionLimit = 0
    config.selection      = .ordered
    let picker = PHPickerViewController(configuration: config)

    let coordinator = PHPickerCoordinatorBox(onSelected: onSelected, onDismiss: onDismiss)
    picker.delegate = coordinator
    // coordinator 需要在 picker 存活期间持有
    objc_setAssociatedObject(picker, &PHPickerCoordinatorBox.key, coordinator, .OBJC_ASSOCIATION_RETAIN)

    guard let root = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows })
        .first(where: { $0.isKeyWindow })?.rootViewController else { return }

    // 找到最顶层 VC 来 present
    var top = root
    while let presented = top.presentedViewController { top = presented }
    top.present(picker, animated: true)
}

final class PHPickerCoordinatorBox: NSObject, PHPickerViewControllerDelegate {
    static var key = "PHPickerCoordinatorBox"
    let onSelected: ([UIImage]) -> Void
    let onDismiss: () -> Void
    init(onSelected: @escaping ([UIImage]) -> Void, onDismiss: @escaping () -> Void) {
        self.onSelected = onSelected; self.onDismiss = onDismiss
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { onDismiss(); return }
        var images = Array(repeating: UIImage(), count: results.count)
        let group = DispatchGroup()
        for (idx, result) in results.enumerated() {
            group.enter()
            result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                if let img = obj as? UIImage { images[idx] = img }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.onSelected(images.filter { $0.size.width > 0 })
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
    @State private var isCapturing = false
    @State private var liveText = ""

    @State private var pptFlow: PPTFlowState = .guide
    @State private var pptPages: [UIImage] = []
    @State private var showDocumentCamera = false
    @State private var retakeIndex: Int? = nil
    @State private var deleteTargetIndex: Int? = nil

    @State private var convertProgress: Double = 0
    @State private var convertTask: Task<Void, Never>? = nil
    @State private var convertTimer: Timer? = nil
    @State private var convertResultURL: URL? = nil
    @State private var showShareSheet = false
    @State private var convertError: String? = nil
    @State private var toastMessage: String? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // ── 拍图识字 ─────────────────────────────────────
                if selectedMode == .scan {
                    ZStack(alignment: .bottom) {
                        // 底层：DataScanner（UIKit），禁止触摸，防止拦截快门
                        scanCameraArea(height: geo.size.height)
                            .allowsHitTesting(false)

                        // 顶层：SwiftUI 控件
                        VStack(spacing: 0) {
                            scanTopToolbar
                            Spacer()
                            // 快门 + modeTabBar 放在同一 VStack，彻底避免 Z 层覆盖问题
                            scanBottomWithTab
                        }
                    }
                }

                // ── 拍PPT ────────────────────────────────────────
                if selectedMode == .ppt {
                    switch pptFlow {
                    case .guide:
                        PPTGuideView(
                            onCamera: { showDocumentCamera = true },
                            onAlbum:  { openPHPicker() },
                            onClose:  { dismissSafely() }
                        )
                        // modeTabBar 悬浮在引导页底部
                        VStack { Spacer(); modeTabBar }

                    case .preview:
                        PPTPreviewView(
                            pages: $pptPages,
                            onCamera:  { retakeIndex = nil; showDocumentCamera = true },
                            onAlbum:   { retakeIndex = nil; openPHPicker() },
                            onRetake:  { idx in retakeIndex = idx; showDocumentCamera = true },
                            onDelete:  { idx in deleteTargetIndex = idx },
                            onConvert: { startConvert() },
                            onAbandon: { pptPages = []; pptFlow = .guide }
                        )

                    case .converting:
                        PPTConvertingView(progress: convertProgress, onStop: { stopConvert() })
                    }
                }

                // ── VNDocumentCamera 全屏 ─────────────────────────
                if showDocumentCamera {
                    DocumentCameraRepresentable(
                        onScanned: { images in handleScanned(images); showDocumentCamera = false },
                        onDismiss: { showDocumentCamera = false }
                    )
                    .ignoresSafeArea()
                }

                // ── 分享 ──────────────────────────────────────────
                if let url = convertResultURL {
                    Color.clear.sheet(isPresented: $showShareSheet) {
                        ShareSheet(url: url)
                    }
                }

                // ── Toast ─────────────────────────────────────────
                if let msg = toastMessage {
                    VStack {
                        Spacer()
                        ToastView(message: msg).padding(.bottom, 100)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
        }
        .alert("删除这一页？", isPresented: .init(
            get: { deleteTargetIndex != nil },
            set: { if !$0 { deleteTargetIndex = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let idx = deleteTargetIndex {
                    pptPages.remove(at: idx)
                    deleteTargetIndex = nil
                    if pptPages.isEmpty { pptFlow = .guide }
                    showToast("已删除，如需恢复请重新拍摄")
                }
            }
            Button("取消", role: .cancel) { deleteTargetIndex = nil }
        } message: { Text("删除后不可恢复，需要重新拍摄") }
        .alert("转化失败", isPresented: .init(
            get: { convertError != nil },
            set: { if !$0 { convertError = nil } }
        )) {
            Button("好", role: .cancel) { convertError = nil }
        } message: { Text(convertError ?? "") }
        .onAppear { checkCameraPermission() }
    }

    // MARK: - 快门 + Tab 合并区（解决 Z 层覆盖问题）
    @ViewBuilder
    private var scanBottomWithTab: some View {
        VStack(spacing: 0) {
            ShutterButton { capturePhoto() }
                .padding(.top, 16).padding(.bottom, 8)
            modeTabBar
        }
        .background(Color.black)
    }

    // MARK: - 模式 Tab
    @ViewBuilder
    private var modeTabBar: some View {
        HStack(spacing: 40) {
            ForEach(CaptureMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedMode = mode
                        if mode == .ppt && pptFlow != .preview { pptFlow = .guide }
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
                    .padding(.vertical, 10).padding(.horizontal, 20)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    // MARK: - 顶部工具栏
    @ViewBuilder
    private var scanTopToolbar: some View {
        HStack {
            Button { dismissSafely() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white).frame(width: 44, height: 44)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 8).background(Color.black)
    }

    // MARK: - 取景区
    @ViewBuilder
    private func scanCameraArea(height: CGFloat) -> some View {
        Group {
            if cameraPermissionDenied {
                CameraPermissionView()
            } else if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                DataScannerRepresentable(
                    onVCReady: { vc in scannerVC = vc },
                    onTextRecognized: { text in liveText = text }
                )
            } else {
                ZStack { Color.black; Text("需要 iOS 16 或以上版本").foregroundColor(.white) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: max(height, 200))
        .ignoresSafeArea()
    }

    // MARK: - PHPicker（UIKit present，绕开 SwiftUI 嵌套 modal bug）
    private func openPHPicker() {
        presentPHPicker(
            onSelected: { images in handlePicked(images) },
            onDismiss:  { }
        )
    }

    // MARK: - 辅助
    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraPermissionDenied = (status == .denied || status == .restricted)
    }

    private func dismissSafely() {
        scannerVC?.stopScanning()
        onDismiss()
    }

    private func capturePhoto() {
        guard !isCapturing, let vc = scannerVC else { return }
        isCapturing = true
        Task {
            do {
                let image = try await vc.capturePhoto()
                await MainActor.run { isCapturing = false; capturedImage = image; dismissSafely() }
            } catch {
                await MainActor.run { isCapturing = false }
            }
        }
    }

    private func handleScanned(_ images: [UIImage]) {
        if let idx = retakeIndex {
            if let first = images.first { pptPages[idx] = first; showToast("第 \(idx+1) 页已更新") }
            retakeIndex = nil
        } else {
            pptPages.append(contentsOf: images)
        }
        selectedMode = .ppt
        pptFlow = .preview
    }

    private func handlePicked(_ images: [UIImage]) {
        if let idx = retakeIndex {
            if let first = images.first { pptPages[idx] = first; showToast("第 \(idx+1) 页已更新") }
            retakeIndex = nil
        } else {
            pptPages.append(contentsOf: images)
        }
        selectedMode = .ppt
        pptFlow = .preview
    }

    private func showToast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { toastMessage = nil }
        }
    }

    // MARK: - 转化
    private func startConvert() {
        pptFlow = .converting; convertProgress = 0; convertError = nil
        convertTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            if self.convertProgress < 0.95 { self.convertProgress = min(self.convertProgress + 0.02, 0.95) }
        }
        convertTask = Task {
            do {
                let url = try await withTimeout(seconds: 120) {
                    try await ConvertService.imagesToPptx(images: self.pptPages)
                }
                await MainActor.run {
                    self.stopTimer(); self.convertProgress = 1.0; self.convertResultURL = url
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.showShareSheet = true; self.pptFlow = .preview
                    }
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run { self.stopTimer(); self.convertError = error.localizedDescription; self.pptFlow = .preview }
            }
        }
    }

    private func stopConvert() {
        convertTask?.cancel(); convertTask = nil; stopTimer()
        pptFlow = .preview; showToast("已停止转化，可重新操作")
    }

    private func stopTimer() { convertTimer?.invalidate(); convertTimer = nil }

    private func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ConvertError.serverError("转化超时，请检查网络后重试")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// MARK: - PPT 引导页
struct PPTGuideView: View {
    let onCamera: () -> Void
    let onAlbum:  () -> Void
    let onClose:  () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white).frame(width: 44, height: 44)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 8)
                Spacer()
                Image(systemName: "doc.richtext.fill").font(.system(size: 64))
                    .foregroundColor(Color(hex: "#34C759")).padding(.bottom, 24)
                Text("扫描幻灯片，生成 PPT")
                    .font(.system(size: 22, weight: .bold)).foregroundColor(.white).padding(.bottom, 8)
                VStack(alignment: .leading, spacing: 14) {
                    PPTGuideStep(number: "1", text: "拍摄 或 从相册选取每一张幻灯片照片")
                    PPTGuideStep(number: "2", text: "预览并整理页面顺序，可删除或重拍")
                    PPTGuideStep(number: "3", text: "一键转化为可编辑的 .pptx 文件并保存")
                }
                .padding(.horizontal, 32).padding(.vertical, 24)
                .background(Color.white.opacity(0.07)).cornerRadius(16)
                .padding(.horizontal, 24).padding(.bottom, 40)
                HStack(spacing: 16) {
                    Button(action: onCamera) {
                        HStack(spacing: 10) {
                            Image(systemName: "camera.fill")
                            Text("拍照扫描").font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.black).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color(hex: "#34C759")).cornerRadius(14)
                    }
                    Button(action: onAlbum) {
                        HStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle")
                            Text("从相册选择").font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.white.opacity(0.15)).cornerRadius(14)
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 80)
            }
        }
    }
}

struct PPTGuideStep: View {
    let number: String; let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(Color(hex: "#34C759").opacity(0.2)).frame(width: 28, height: 28)
                Text(number).font(.system(size: 13, weight: .bold)).foregroundColor(Color(hex: "#34C759"))
            }
            Text(text).font(.system(size: 14)).foregroundColor(Color(white: 0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

// MARK: - PPT 预览管理页
struct PPTPreviewView: View {
    @Binding var pages: [UIImage]
    let onCamera: () -> Void; let onAlbum: () -> Void
    let onRetake: (Int) -> Void; let onDelete: (Int) -> Void
    let onConvert: () -> Void; let onAbandon: () -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible()),
                            GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        ZStack {
            Color(hex: "#1C1C1E").ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button("放弃", action: onAbandon).font(.system(size: 16)).foregroundColor(Color(white: 0.6))
                    Spacer()
                    Text("PPT 预览 (\(pages.count)页)").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    Spacer()
                    Button(action: onConvert) {
                        Text("转化").font(.system(size: 16, weight: .semibold))
                            .foregroundColor(pages.isEmpty ? .gray : Color(hex: "#34C759"))
                    }.disabled(pages.isEmpty)
                }
                .padding(.horizontal, 20).padding(.vertical, 14).background(Color(hex: "#2C2C2E"))

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { idx, img in
                            PPTPageTile(image: img, index: idx,
                                        onRetake: { onRetake(idx) }, onDelete: { onDelete(idx) })
                        }
                    }
                    .padding(16).padding(.bottom, 80)
                }
                Spacer(minLength: 0)
            }
            VStack {
                Spacer()
                HStack(spacing: 0) {
                    Button(action: onAlbum) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle")
                            Text("从相册选下一张").font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color(hex: "#2C2C2E"))
                    }
                    Divider().frame(width: 1).background(Color.gray.opacity(0.3))
                    Button(action: onCamera) {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                            Text("拍下一张").font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color(hex: "#3A3A3C"))
                    }
                }
                .frame(height: 56)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

struct PPTPageTile: View {
    let image: UIImage; let index: Int
    let onRetake: () -> Void; let onDelete: () -> Void
    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(height: 80).clipped().cornerRadius(8)
                Button(action: onDelete) {
                    ZStack {
                        Circle().fill(Color.black.opacity(0.6)).frame(width: 22, height: 22)
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                    }
                }.padding(4)
            }
            Text("第 \(index + 1) 页").font(.system(size: 11, weight: .medium)).foregroundColor(Color(white: 0.7))
            Button(action: onRetake) {
                Text("点击重拍").font(.system(size: 11, weight: .medium)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
                    .background(Color(white: 0.3)).cornerRadius(5)
            }
        }
    }
}

// MARK: - PPT 转化进度页
struct PPTConvertingView: View {
    let progress: Double; let onStop: () -> Void
    var progressPercent: Int { Int(progress * 100) }
    var body: some View {
        ZStack {
            Color(hex: "#1C1C1E").ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 56))
                    .foregroundColor(Color(hex: "#34C759"))
                    .rotationEffect(.degrees(progress * 360))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: progress)
                VStack(spacing: 12) {
                    Text("正在转化为 PPT…").font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                    Text("请保持网络连接，请勿关闭应用").font(.system(size: 13)).foregroundColor(Color(white: 0.55))
                }
                VStack(spacing: 8) {
                    ProgressView(value: progress).tint(Color(hex: "#34C759")).padding(.horizontal, 40)
                    Text("\(progressPercent)%").font(.system(size: 14, weight: .medium)).foregroundColor(Color(hex: "#34C759"))
                }
                Button(action: onStop) {
                    Text("停止生成").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 200).padding(.vertical, 14)
                        .background(Color(hex: "#FF3B30")).cornerRadius(14)
                }
                Spacer()
            }
        }
    }
}

// MARK: - 分享
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#Preview {
    CameraView(capturedImage: .constant(nil), onDismiss: {})
}
