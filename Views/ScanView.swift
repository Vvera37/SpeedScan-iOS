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
    @State private var showPHPicker = false          // 换成 PHPicker，替代旧 UIImagePickerController
    @State private var showCameraView = false
    @State private var showDocumentPicker = false
    @State private var isConvertingPPT = false
    @State private var pptConvertError: String? = nil
    #if DEBUG
    @State private var showDebugTestPDF = false
    #endif
    @State private var showResult = false
    @State private var showLoginSheet = false

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
            Color.white.ignoresSafeArea()
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
            ScanPHPickerView(selectedImage: $viewModel.selectedImage, isPresented: $showPHPicker)
        }
        .fullScreenCover(isPresented: $showCameraView) { cameraViewContent }
        .fileImporter(isPresented: $showDocumentPicker, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { handlePDFImport($0) }
        .fullScreenCover(isPresented: $showResult) {
            if let result = viewModel.scanResult {
                ScanResultView(result: result, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView(isModal: true).environmentObject(appState)
        }
        .onChange(of: viewModel.selectedImage) { _, newImage in
            guard newImage != nil else { return }
            if appState.recordGuestScan() {
                viewModel.performOCR()
            } else {
                Task { @MainActor in viewModel.selectedImage = nil; showLoginSheet = true }
            }
        }
        .onChange(of: viewModel.scanResult) { _, result in if result != nil { showResult = true } }
        .onChange(of: appState.showLoginRequired) { _, show in
            if show { showLoginSheet = true; appState.showLoginRequired = false }
        }
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
                ScanActionCard(icon: "camera.fill", title: "拍照扫描", subtitle: "实时拍摄识别",
                               gradient: [Color(hex: "#007AFF"), Color(hex: "#0055CC")]) { showCameraView = true }
                ScanActionCard(icon: "photo.on.rectangle", title: "相册导入", subtitle: "从图库选择",
                               gradient: [Color(hex: "#34C759"), Color(hex: "#248A3D")]) { showPHPicker = true }
            }
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

    private var cameraViewContent: some View {
        CameraView(
            capturedImage: $viewModel.selectedImage,
            onDismiss: { showCameraView = false },
            onPPTDone: { pages in
                showCameraView = false
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

    private func handlePDFImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard appState.recordGuestScan() else { showLoginSheet = true; return }
            _ = url.startAccessingSecurityScopedResource()
            isConvertingPPT = true
            Task {
                do {
                    let docxUrl = try await ConvertService.pdfToWord(pdfUrl: url)
                    url.stopAccessingSecurityScopedResource()
                    await MainActor.run {
                        isConvertingPPT = false
                        let av = UIActivityViewController(activityItems: [docxUrl], applicationActivities: nil)
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let root = scene.windows.first?.rootViewController { root.present(av, animated: true) }
                    }
                } catch {
                    url.stopAccessingSecurityScopedResource()
                    await MainActor.run { isConvertingPPT = false; pptConvertError = error.localizedDescription }
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
        .background(Color.white)
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
        .background(Color.white)
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
    @Binding var selectedImage: UIImage?
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
                    self.parent.selectedImage = obj as? UIImage
                }
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
