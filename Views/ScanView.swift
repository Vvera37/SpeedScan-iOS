//
// 扫描界面 - 核心功能
//

import SwiftUI
import Vision

struct ScanView: View {
    @StateObject private var viewModel = ScanViewModel()
    @State private var showImagePicker = false
    @State private var sourceType: UIImagePickerController.SourceType = .camera
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 顶部操作区
                HStack(spacing: 20) {
                    ScanButton(
                        icon: "camera.fill",
                        title: NSLocalizedString("btn_camera", comment: ""),
                        action: {
                            sourceType = .camera
                            showImagePicker = true
                        }
                    )
                    
                    ScanButton(
                        icon: "photo.fill",
                        title: NSLocalizedString("btn_import", comment: ""),
                        action: {
                            sourceType = .photoLibrary
                            showImagePicker = true
                        }
                    )
                }
                .padding(.top, 30)
                
                // 扫描结果预览
                if viewModel.isProcessing {
                    VStack(spacing: 16) {
                        ProgressView(NSLocalizedString("processing", comment: ""))
                            .scaleEffect(1.2)
                        Text(NSLocalizedString("ocr_processing", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if let result = viewModel.scanResult {
                    ScanResultView(result: result, viewModel: viewModel)
                } else {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.5))
                        Text(NSLocalizedString("hint_scan", comment: ""))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    Spacer()
                }
            }
            .navigationTitle(NSLocalizedString("app_name", comment: ""))
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(sourceType: sourceType, selectedImage: $viewModel.selectedImage)
            }
            .onChange(of: viewModel.selectedImage) { newImage in
                if newImage != nil {
                    viewModel.performOCR()
                }
            }
            .alert(item: $viewModel.alertItem) { alert in
                Alert(title: alert.title, message: alert.message, dismissButton: alert.dismissButton)
            }
        }
    }
}

// MARK: - 扫描按钮
struct ScanButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .blue.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 预览
struct ScanView_Previews: PreviewProvider {
    static var previews: some View {
        ScanView()
            .environmentObject(AppState())
    }
}
