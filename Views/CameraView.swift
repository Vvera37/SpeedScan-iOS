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
        // 透明背景确保系统响应链能识别到按钮点击区域（专家建议）
        .background(Color.black.opacity(0.001))
        .contentShape(Circle().size(CGSize(width: 80, height: 80)))
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
            isHighlightingEnabled: false  // 关闭高亮框，避免拍照时把 overlay 拍进图片
        )
        scanner.delegate = context.coordinator
        context.coordinator.onVCReady       = onVCReady
        context.coordinator.onTextRecognized = onTextRecognized

        // 等 VC 加入视图层级后再 startScanning，不依赖 updateUIViewController 时序
        // 原因：updateUIViewController 在父视图重渲染时会多次调用，第一次相机还没准备好会抛异常，
        // 导致 onVCReady 永远不触发，scannerVC 一直为 nil，快门永远失效
        DispatchQueue.main.async {
            guard !scanner.isScanning else { return }
            do {
                try scanner.startScanning()
                context.coordinator.onVCReady?(scanner)
                context.coordinator.onVCReady = nil
                print("✅ DataScanner 启动成功，scannerVC 已赋值")
            } catch {
                print("❌ startScanning 失败：\(error)")
            }
        }
        return scanner
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        // startScanning 已在 makeUIViewController 的 async 里处理，这里留空
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
    static var key: UInt8 = 0
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

    // 手写/图片识别（Claude Vision）
    @State private var isRecognizing = false
    @State private var ocrResult: String? = nil
    @State private var ocrError: String? = nil
    @State private var showOCRResult = false

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
    @State private var showPDFDoneAlert = false   // 生成成功确认弹窗
    @State private var convertError: String? = nil
    @State private var toastMessage: String? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // ── 拍图识字 ─────────────────────────────────────
                if selectedMode == .scan {
                    // 物理隔离：VStack 线性排列，cameraArea 不延伸到按钮下方
                    // zIndex 明确层级，bottomArea 最高保证响应链优先
                    VStack(spacing: 0) {
                        scanTopToolbar
                            .zIndex(1)
                        scanCameraArea(height: geo.size.height - 180)
                            .clipped()
                            .zIndex(0)
                        scanBottomWithTab
                            .background(Color.black)
                            .zIndex(2)
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
                        ShareSheet(url: url) {
                            // 用户分享或取消后回到管理页面，这时弹确认弹窗
                            showShareSheet = false
                            showPDFDoneAlert = true
                        }
                    }
                }

                // ── OCR 识别中 loading ────────────────────────────
                if isRecognizing {
                    ZStack {
                        Color.black.opacity(0.65).ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            Text("正在识别文字…")
                                .foregroundColor(.white)
                                .font(.system(size: 15))
                        }
                    }
                    .allowsHitTesting(true)
                    .zIndex(8)
                }

                // ── OCR 识别结果页 ─────────────────────────────────
                if showOCRResult, let text = ocrResult {
                    OCRResultView(
                        initialText: text,
                        onDismiss: {
                            showOCRResult = false
                            ocrResult = nil
                            // 关闭结果页后重启扫描，让用户可以继续拍
                            if let vc = scannerVC {
                                try? vc.startScanning()
                            }
                        }
                    )
                    .transition(.move(edge: .bottom))
                    .zIndex(10)
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
        .alert("识别失败", isPresented: .init(
            get: { ocrError != nil },
            set: { if !$0 { ocrError = nil } }
        )) {
            Button("好", role: .cancel) { ocrError = nil }
        } message: { Text(ocrError ?? "") }
        // PDF 生成成功确认弹窗
        // 触发时机：用户从分享sheet返回管理页面后
        // 「重新生成」→ 重新拉起分享sheet（同一份 PDF），方便再次保存/分享到其他 app
        // 「完成，关闭此页」→ 清空数据，dismiss CameraView 回首页
        .alert("PDF 已生成 ✓", isPresented: $showPDFDoneAlert) {
            Button("重新生成") {
                // 再次拉起同一份 PDF 的分享 sheet
                showShareSheet = true
            }
            Button("完成，关闭此页") {
                // 清空页面数据，回到首页
                pptPages = []
                convertResultURL = nil
                pptFlow = .guide
                dismissSafely()
            }
        } message: {
            Text("PDF 文件已成功生成。\n可重新拉起分享，或完成并返回首页。")
        }
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
                    onTextRecognized: { _ in }  // DataScanner 实时识别仅用于取景框高亮，不保存文字
                )
            } else {
                ZStack { Color.black; Text("需要 iOS 16 或以上版本").foregroundColor(.white) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: max(height, 200))
        // 不加 .ignoresSafeArea()，否则 UIKit 视图会物理延伸覆盖快门按钮区域
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
        print("📸 快门触发，isCapturing=\(isCapturing), scannerVC=\(scannerVC != nil)")
        guard !isCapturing, let vc = scannerVC else { return }
        isCapturing = true

        // capturePhoto() 设计为在 scanning 状态下直接调用，不需要 stopScanning
        // 之前 stopScanning 反而导致相机帧停了，拍到空图
        Task {
            do {
                let image = try await vc.capturePhoto()
                print("✅ capturePhoto 成功，size=\(image.size)")
                await MainActor.run {
                    self.isCapturing = false
                    self.startOCR(image: image)
                }
            } catch {
                print("❌ capturePhoto 失败：\(error)，尝试截图兜底")
                // 兜底：capturePhoto 失败时截当前视图（此时扫描还在跑，画面有内容）
                await MainActor.run {
                    let renderer = UIGraphicsImageRenderer(bounds: vc.view.bounds)
                    let fallback = renderer.image { _ in
                        vc.view.drawHierarchy(in: vc.view.bounds, afterScreenUpdates: false)
                    }
                    self.isCapturing = false
                    if fallback.size.width > 0 {
                        self.startOCR(image: fallback)
                    } else {
                        self.ocrError = "拍照失败，请重试"
                    }
                }
            }
        }
    }

    private func startOCR(image: UIImage) {
        isRecognizing = true
        Task {
            do {
                let text = try await OCRService.recognizeHandwriting(image: image)
                await MainActor.run {
                    isRecognizing = false
                    ocrResult = text
                    showOCRResult = true
                }
            } catch {
                await MainActor.run {
                    isRecognizing = false
                    ocrError = error.localizedDescription
                }
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
                    try await ConvertService.imagesToPdf(images: self.pptPages)
                }
                await MainActor.run {
                    self.stopTimer()
                    self.convertProgress = 1.0
                    self.convertResultURL = url
                    // 进度跑完后 0.5s 先回到预览页，再弹分享sheet
                    // 分享完成后（ShareSheet.onDismiss）再弹确认弹窗
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.pptFlow = .preview
                        self.showShareSheet = true
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
                Text("拍照扫描，生成 PDF")
                    .font(.system(size: 22, weight: .bold)).foregroundColor(.white).padding(.bottom, 8)
                VStack(alignment: .leading, spacing: 14) {
                    PPTGuideStep(number: "1", text: "拍摄 或 从相册选取每一张图片")
                    PPTGuideStep(number: "2", text: "预览并整理页面顺序，可删除或重拍")
                    PPTGuideStep(number: "3", text: "一键合并为 PDF 文件并保存分享")
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

    @State private var showAbandonAlert = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible()),
                            GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        ZStack {
            Color(hex: "#1C1C1E").ignoresSafeArea()
            VStack(spacing: 0) {
                // 顶部导航栏
                HStack {
                    Button(action: { showAbandonAlert = true }) {
                        Text("放弃")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: "#FF3B30"))
                    }
                    Spacer()
                    Text("PPT 预览 (\(pages.count)页)")
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    Spacer()
                    Button(action: onConvert) {
                        Text("生成 PDF")
                            .font(.system(size: 16, weight: .semibold))
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
                    .padding(16).padding(.bottom, 100)
                }
                Spacer(minLength: 0)
            }

            // 底部操作栏（重新设计）
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    // 从相册选
                    Button(action: onAlbum) {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.fill")
                                .font(.system(size: 20))
                            Text("从相册添加")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "#2C2C2E"))
                        .cornerRadius(14)
                    }
                    // 拍照
                    Button(action: onCamera) {
                        VStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 20))
                            Text("拍下一张")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "#34C759"))
                        .cornerRadius(14)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .background(
                    Color(hex: "#1C1C1E")
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: -4)
                )
            }
            .ignoresSafeArea(edges: .bottom)
        }
        // 放弃确认弹窗
        .alert("放弃本次扫描？", isPresented: $showAbandonAlert) {
            Button("放弃", role: .destructive) { onAbandon() }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("已扫描的 \(pages.count) 张图片将全部丢弃，且无法恢复。如需保留，请先完成转化。")
        }
    }
}

struct PPTPageTile: View {
    let image: UIImage; let index: Int
    let onRetake: () -> Void; let onDelete: () -> Void

    // 固定宽高比 3:4（接近 PPT 幻灯片比例），宽度由 Grid 决定，高度固定等比
    private let tileAspect: CGFloat = 4.0 / 3.0  // height / width

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .topTrailing) {
                    // 等比缩放填满固定框，超出部分裁剪，不变形
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.width * tileAspect)
                        .clipped()
                        .cornerRadius(8)

                    Button(action: onDelete) {
                        ZStack {
                            Circle().fill(Color.black.opacity(0.6)).frame(width: 22, height: 22)
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                        }
                    }.padding(4)
                }
            }
            .aspectRatio(1.0 / tileAspect, contentMode: .fit)  // 让 GeometryReader 有固定高度

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
                    Text("正在生成 PDF…").font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
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

// MARK: - 分享（分享完成后回调 onDismiss，让调用方关闭页面）
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    var onDismiss: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in
            onDismiss?()
        }
        return vc
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#Preview {
    CameraView(capturedImage: .constant(nil), onDismiss: {})
}
