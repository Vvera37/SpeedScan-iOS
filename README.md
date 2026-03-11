# 极速扫描

这是一个完整的 Xcode iOS 项目。

## 快速开始

### 方法1: 直接在 Xcode 中打开 (推荐)

1. 打开 **Xcode**
2. 选择 **File → Open...**
3. 导航到 `~/Documents/OpenClawWorkspace/projects/极速扫描`
4. 选择 **极速扫描** 文件夹，点击 **Open**
5. Xcode 会自动识别 Swift 文件结构
6. 按 **⌘+R** 运行

### 方法2: 使用 XcodeGen

```bash
# 安装 XcodeGen (如果还没安装)
brew install xcodegen

# 生成项目
cd ~/Documents/OpenClawWorkspace/projects/极速扫描
xcodegen generate

# 打开项目
open 极速扫描.xcodeproj
```

### 方法3: 使用设置脚本

```bash
cd ~/Documents/OpenClawWorkspace/projects/极速扫描
./setup-xcode.sh
```

## 项目结构

```
极速扫描/
├── SpeedScanApp.swift           # App 入口
├── Info.plist                   # 应用配置
├── Views/                       # 界面
│   ├── ContentView.swift        # 主容器
│   ├── ScanView.swift           # 扫描界面
│   ├── ScanResultView.swift     # 结果展示
│   ├── LoginView.swift          # 登录
│   ├── HistoryView.swift        # 历史记录
│   └── SettingsView.swift       # 设置
├── ViewModels/
│   └── ScanViewModel.swift      # OCR 逻辑
├── Components/
│   └── ImagePicker.swift        # 图片选择
└── Resources/
    ├── Assets.xcassets/         # 图标
    └── Localizable.strings      # 国际化
```

## 开发要求

- **Xcode**: 14.0+
- **iOS**: 16.0+
- **Swift**: 5.7+

## 功能特点

- 📷 拍照/导入图片识别
- 📝 Vision 框架端侧 OCR
- 🌐 多语言支持
- 💰 会员系统 (StoreKit)
- 📚 历史记录管理

## 注意事项

1. 首次运行需要在 **Signing & Capabilities** 中选择你的开发团队
2. 真机运行需要 Apple Developer 账号
3. 模拟器可以测试大部分功能（除了相机）

---

详细文档请查看外层 README.md
