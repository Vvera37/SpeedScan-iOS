//
// 扫描界面 - 核心功能
//

import SwiftUI
import Vision

struct ScanView: View {
    @StateObject private var viewModel = ScanViewModel()
    @State private var showImagePicker = false
    @State private var sourceType: UIImagePickerController.SourceType = .camera
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 顶部操作区
                HStack(spacing: 20) {
                    ScanButton(
                        icon: "camera.fill",
                        title: LocalizedStringKey("btn_camera"),
                        action: {
                            sourceType = .camera
                            showImagePicker = true
                        }
                    )
                    
                    ScanButton(
                        icon: "photo.fill",
                        title: LocalizedStringKey("btn_import"),
                        action: {
                            sourceType = .photoLibrary
                            showImagePicker = true
                        }
                    )
                }
                .padding(.top, 30)
                
                // 扫描结果预览
                if viewModel.isProcessing {
                    ProgressView(LocalizedStringKey("processing"))
                        .scaleEffect(1.2)
                        .padding()
                } else if let result = viewModel.scanResult {
                    ScanResultView(result: result, viewModel: viewModel)
                } else {
                    Spacer()
                    Text(LocalizedStringKey("hint_scan"))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            }
            .navigationTitle(LocalizedStringKey("app_name"))
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(sourceType: sourceType, selectedImage: $viewModel.selectedImage)
            }
            .onChange(of: viewModel.selectedImage) { newImage in
                if newImage != nil {
                    viewModel.performOCR()
                }
            }
        }
    }
}

// MARK: - 扫描按钮
struct ScanButton: View {
    let icon: String
    let title: LocalizedStringKey
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
                    .background(Color.blue)
                    .cornerRadius(20)
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
        }
    }
}
