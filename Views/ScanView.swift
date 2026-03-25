//
// ScanView.swift
// 首页扫描界面 — 精修 UI 对标夸克扫描王
//

import SwiftUI
import Vision
import SwiftData
import PhotosUI

struct ScanView: View {
    @StateObject private var viewModel = ScanViewModel()
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showPHPicker = false
    @State private var showSystemCamera = false      // 拍照识字：直接弹系统相机
    @State private var showPPTCamera = false         // 拍PPT：走 CameraView（VNDocumentCamera）
    @State private var showDocumentPicker = false
    @State private var isConvertingPPT = false
    @State private var pptConvertError: String? = nil
    @State private var showResult = false
    @State private var showLoginSheet = false
    // OCR 结果页（Claude Vision）
    @State private var isRecognizing = false
    @State private var ocrResult: String? = nil
    @State private var ocrImage: UIImage? = nil
    @State private var ocrError: String? = nil
    @State private var showOCRResult = false

    // 最近记录（SwiftData）
    @Query(sort: \ScanRecord.createdAt, order: .reverse) private var recentRecords: [ScanRecord]

        var body: some View {
        NavigationStack {
            scanContentView.navigationBarHidden(true)
        }
    }

    // MARK: - 主内容拆分（避免 body 类型推断超时）
    private var scanContentView: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    scanHeaderView
                    scanActionCards
                    if viewModel.isProcessing { ProcessingCard().padding(.horizontal, 20) }
                    scanRecentRecords
                    Spacer(minLength: 40)
                }
            }
        }
        .overlay { convertingOverlay }
        .alert("转换失败", isPresented: .init(
            get: { pptConvertError != nil },
            set: { if !$0 { pptConvertError = nil } }
        )) {
            Button("好") { pptConvertError = nil }
        } message: { Text(pptConvertError ?? "") }
        .sheet(isPresented: $showPHPicker) {
            ScanPHPickerView(
                onSelected: { image in
                    showPHPicker = false
                    guard appState.recordGuestScan() else { showLoginSheet = true; return }
                    startOCR(image: image)
                },
                isPresented: $showPHPicker
            )
        }
        // 拍照识字：系统相机
        .fullScreenCover(isPresented: $showSystemCamera) {
            SystemCameraView(
                onPhoto: { image in
                    showSystemCamera = false
                    startOCR(image: image)
                },
                onDismiss: { showSystemCamera = false }
            )
            .ignoresSafeArea()
        }
        // OCR 结果页
        .fullScreenCover(isPresented: $showOCRResult) {
            if let text = ocrResult {
                OCRResultView(
                    initialText: text,
                    originalImage: ocrImage ?? UIImage(),
                    onDismiss: {
                        showOCRResult = false
                        ocrResult = nil
                        ocrImage = nil
                    }
                )
                .environmentObject(subscriptionManager)
            }
        }
        // 拍PPT
        .fullScreenCover(isPresented: $showPPTCamera) { pptCameraContent }
        .fileImporter(isPresented: $showDocumentPicker, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { handlePDFImport($0) }
        .fullScreenCover(isPresented: $showResult) {
            if let result = viewModel.scanResult {
                ScanResultView(result: result, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView(isModal: true).environmentObject(appState)
        }
        // loading 用 overlay 不用 fullScreenCover，避免多个 cover 同时触发冲突
        // colorScheme(.dark) 隔离深色环境，防止影响外层 Color.primary 解析
        .overlay {
            if isRecognizing {
                OCRLoadingView()
                    .ignoresSafeArea()
                    .colorScheme(.dark)
            }
        }
        // showResult 由 startOCR 手动触发（延迟0.1s避免cover冲突），不再用 onChange 自动触发
        .onChange(of: appState.showLoginRequired) { _, show in
            if show { showLoginSheet = true; appState.showLoginRequired = false }
        }
        .alert("识别失败", isPresented: .init(get: { ocrError != nil }, set: { if !$0 { ocrError = nil } })) {
            Button("好", role: .cancel) { ocrError = nil }
        } message: { Text(ocrError ?? "") }
        .alert(item: $viewModel.alertItem) { alert in
            Alert(title: alert.title, message: alert.message, dismissButton: alert.dismissButton)
        }
    }

    private var scanHeaderView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("扫描鸡").font(.system(size: 32, weight: .bold)).foregroundColor(.primary)
                Text("智能 OCR · 文字识别").font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "camera.viewfinder").font(.system(size: 28)).foregroundColor(Color(hex: "#007AFF"))
        }
        .padding(.horizontal, 20).padding(.top, 16)
    }

    private var scanActionCards: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ScanActionCard(icon: "camera.fill", title: "拍照扫描", subtitle: "拍照识别文字",
                               gradient: [Color(hex: "#007AFF"), Color(hex: "#0055CC")]) { showSystemCamera = true }
                ScanActionCard(icon: "photo.on.rectangle", title: "相册导入", subtitle: "选图片识别文字，可导出 Word",
                               gradient: [Color(hex: "#34C759"), Color(hex: "#248A3D")]) { showPHPicker = true }
            }
            ScanActionCardWide(icon: "photo.stack.fill", title: "拍照转 PDF",
                               subtitle: "多张拍摄，一键合并为 PDF 文件",
                               gradient: [Color(hex: "#5856D6"), Color(hex: "#3634A3")]) { showPPTCamera = true }
            ScanActionCardWide(icon: "doc.richtext.fill", title: "PDF 转 Word",
                               subtitle: "导入 PDF，一键转为可编辑 Word 文档",
                               gradient: [Color(hex: "#FF9500"), Color(hex: "#CC7700")]) { showDocumentPicker = true }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var scanRecentRecords: some View {
        if !recentRecords.isEmpty && !viewModel.isProcessing {
            VStack(alignment: .leading, spacing: 12) {
                Text("最近扫描").font(.headline).foregroundColor(.primary).padding(.horizontal, 20)
                ForEach(recentRecords.prefix(2)) { record in
                    RecentRecordRow(record: record).padding(.horizontal, 20)
                }
            }
        }
    }

    @ViewBuilder
    private var convertingOverlay: some View {
        if isConvertingPPT {
            ZStack {
                Color.black.opacity(0.5).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(1.5)
                    Text("正在转换，请稍候…").foregroundColor(.white).font(.system(size: 15))
                }
                .padding(32).background(Color(white: 0.15)).cornerRadius(16)
            }
        }
    }

    // 拍PPT 入口（CameraView 只保留 PPT 流程）
    private var pptCameraContent: some View {
        CameraView(
            capturedImage: $viewModel.selectedImage,
            onDismiss: { showPPTCamera = false },
            onPPTDone: { pages in
                showPPTCamera = false
                guard !pages.isEmpty else { return }
                isConvertingPPT = true
                Task {
                    do {
                        let url = try await ConvertService.imagesToPdf(images: pages)
                        await MainActor.run {
                            isConvertingPPT = false
                            let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let root = scene.windows.first?.rootViewController { root.present(av, animated: true) }
                        }
                    } catch {
                        await MainActor.run { isConvertingPPT = false; pptConvertError = error.localizedDescription }
                    }
                }
            }
        )
    }

    private func startOCR(image: UIImage) {
        isRecognizing = true
        ocrImage = image
        Task {
            // 第一步：先跑本地 Vision OCR（毫秒级，免费）
            // 判断逻辑：置信度 >= 0.82 且识别到 >= 15 个字符 → 印刷体，直接走本地结果
            // 否则 → 手写/模糊，切 Claude Vision
            if let localResult = await tryLocalOCR(image: image),
               localResult.confidence >= 0.82,
               localResult.text.count >= 15 {
                // 印刷体：走 ScanResultView 流程
                // 先关 loading，等下一帧再弹结果页，避免两个 cover 同帧冲突
                await MainActor.run {
                    isRecognizing = false
                    viewModel.selectedImage = image
                    viewModel.scanResult = localResult.ocrResult
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                await MainActor.run { showResult = true }
                return
            }

            // 手写/低置信度：走 Claude Vision（压缩在 OCRService 内部处理）
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

    // 本地 Vision OCR 预检，返回置信度和文字
    private func tryLocalOCR(image: UIImage) async -> (text: String, confidence: Double, ocrResult: OCRResult)? {
        guard let cgImage = image.cgImage else { return nil }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [
            Locale.Language(identifier: "zh-Hans"),
            Locale.Language(identifier: "zh-Hant"),
            Locale.Language(identifier: "en-US")
        ]
        request.automaticallyDetectsLanguage = true
        guard let observations = try? await request.perform(on: cgImage, orientation: .up),
              !observations.isEmpty else { return nil }

        let totalConf = observations.compactMap { $0.topCandidates(1).first?.confidence }.reduce(0, +)
        let avgConf = Double(totalConf / Float(observations.count))
        let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")

        let result = OCRResult(
            originalImage: image,
            recognizedText: text,
            detectedLanguage: "zh-Hans",
            confidence: avgConf,
            timestamp: Date(),
            pages: []
        )
        return (text, avgConf, result)
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }
        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func handlePDFImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard appState.recordGuestScan() else { showLoginSheet = true; return }
            _ = url.startAccessingSecurityScopedResource()
            isConvertingPPT = true
            Task {
                // 本地方案：PDFKit 提取文字 → DocxExporter 生成 Word
                // 不走后端，彻底解决中文方格问题（字体由 Word 客户端渲染）
                await viewModel.processPDF(url: url)
                url.stopAccessingSecurityScopedResource()
                await MainActor.run {
                    isConvertingPPT = false
                    guard viewModel.scanResult != nil else {
                        pptConvertError = "PDF 文字提取失败，请确认文件完整"
                        return
                    }
                    // 用 DocxExporter 本地生成 Word
                    let isPremium = subscriptionManager.isPremium
                    Task {
                        guard let filePath = await viewModel.exportWord(isPremium: isPremium) else {
                            await MainActor.run { pptConvertError = "Word 文件生成失败" }
                            return
                        }
                        await MainActor.run {
                            let docxUrl = URL(fileURLWithPath: filePath)
                            let av = UIActivityViewController(activityItems: [docxUrl], applicationActivities: nil)
                            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let root = scene.windows.first?.rootViewController {
                                root.present(av, animated: true)
                            }
                        }
                    }
                }
            }
        case .failure(let error):
            viewModel.showAlert(title: "文件选择失败", message: error.localizedDescription)
        }
    }
}

// MARK: - 双列操作卡片
struct ScanActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(
                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .cornerRadius(16)
            .shadow(color: gradient.first?.opacity(0.35) ?? .clear, radius: 12, x: 0, y: 6)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - 宽版操作卡片（PDF）
struct ScanActionCardWide: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(16)
            .shadow(color: gradient.first?.opacity(0.3) ?? .clear, radius: 10, x: 0, y: 5)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - 处理中卡片
struct ProcessingCard: View {
    @State private var dotCount = 1
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#007AFF")))
                .scaleEffect(1.2)
            VStack(alignment: .leading, spacing: 4) {
                Text("正在识别中" + String(repeating: ".", count: dotCount))
                    .font(.system(size: 15, weight: .medium))
                Text("使用 Vision 端侧 OCR 引擎")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        .onReceive(timer) { _ in
            dotCount = dotCount % 3 + 1
        }
    }
}

// MARK: - 最近记录行
struct RecentRecordRow: View {
    let record: ScanRecord

    var body: some View {
        HStack(spacing: 14) {
            // 文档图标
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "#007AFF").opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: "#007AFF"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(record.textPreview.isEmpty ? "(无文字内容)" : String(record.textPreview.prefix(60)))
                    .font(.system(size: 14))
                    .lineLimit(2)
                    .foregroundColor(.primary)
                HStack(spacing: 8) {
                    Text(record.formattedDate)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(record.languageDisplayName)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(hex: "#007AFF").opacity(0.1))
                        .foregroundColor(Color(hex: "#007AFF"))
                        .cornerRadius(4)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13))
                .foregroundColor(Color.secondary.opacity(0.5))
        }
        .padding(16)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 按压缩放样式
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Color Hex 扩展
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - 首页相册单选 PHPicker（单张，替代 UIImagePickerController 避免白页）
struct ScanPHPickerView: UIViewControllerRepresentable {
    var onSelected: (UIImage) -> Void
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ScanPHPickerView
        init(_ parent: ScanPHPickerView) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            guard let result = results.first else { return }
            result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                DispatchQueue.main.async {
                    if let img = obj as? UIImage { self.parent.onSelected(img) }
                }
            }
        }
    }
}

// MARK: - OCR 识别中 loading 全屏页
struct OCRLoadingView: View {
    @State private var dots = 1
    @State private var pulse = false
    private let tips = [
        "正在分析图片内容…",
        "识别文字中，请稍候…",
        "AI 正在努力识别…",
        "马上就好…"
    ]
    @State private var tipIndex = 0
    private let timer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(hex: "#1C1C1E").ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                // 动态图标
                ZStack {
                    Circle()
                        .fill(Color(hex: "#007AFF").opacity(0.15))
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulse ? 1.12 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 52))
                        .foregroundColor(Color(hex: "#007AFF"))
                }
                .onAppear { pulse = true }

                VStack(spacing: 12) {
                    Text(tips[tipIndex])
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .animation(.easeInOut, value: tipIndex)
                    Text("通常需要 5–15 秒")
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: 0.5))
                }

                // 进度条（模拟进度，让用户感知在走）
                OCRSimulatedProgressBar()
                    .padding(.horizontal, 48)

                Spacer()
            }
        }
        .onReceive(timer) { _ in
            tipIndex = (tipIndex + 1) % tips.count
        }
    }
}

struct OCRSimulatedProgressBar: View {
    @State private var progress: CGFloat = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.25))
                    .frame(height: 4)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "#007AFF"))
                    .frame(width: geo.size.width * progress, height: 4)
                    .animation(.easeInOut(duration: 0.4), value: progress)
            }
        }
        .frame(height: 4)
        .onReceive(timer) { _ in
            // 模拟进度：快速到 70%，然后放慢等真实结果
            if progress < 0.7 {
                progress = min(progress + 0.08, 0.7)
            } else if progress < 0.92 {
                progress = min(progress + 0.015, 0.92)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ScanView()
        .environmentObject(AppState())
        .environmentObject(SubscriptionManager())
}
