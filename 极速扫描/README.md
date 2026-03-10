# 极速扫描 - iOS App

## 产品定位
专注扫描和文字识别的端侧AI工具。

**产品宣言**: 更快、更准确、更便宜

## 技术架构
- **框架**: SwiftUI + Vision框架
- **OCR**: Apple Vision (端侧，无云端)
- **存储**: 本地文件系统
- **支付**: StoreKit内购

## 核心功能
1. **拍照/导入识别** - 端侧AI文字识别，极速处理
2. **文字面板** - 长按复制部分内容，一键复制全文
3. **多语言翻译** - 非中文自动检测，一键翻译
4. **导出Word** - 生成.docx文件，本地存储
5. **PDF转换** - 保留图片位置，生成Word文档

## 付费模式
- 免费: 有水印
- ¥12/年 或 ¥2/月: 去水印，无限制

## 文件结构
```
极速扫描/
├── SpeedScanApp.swift          # App入口
├── Views/
│   ├── ContentView.swift       # 主容器
│   ├── ScanView.swift          # 扫描界面
│   ├── ScanResultView.swift    # 结果展示
│   ├── LoginView.swift         # 手机号登录
│   ├── HistoryView.swift       # 历史记录
│   └── SettingsView.swift      # 设置/会员
├── ViewModels/
│   └── ScanViewModel.swift     # OCR逻辑
├── Components/
│   └── ImagePicker.swift       # 图片选择
└── Resources/
    └── Localizable.strings     # 国际化文件
```

## TODO清单
- [ ] StoreKit内购集成
- [ ] Word文档生成（使用docx库）
- [ ] PDF转Word功能
- [ ] 翻译API集成
- [ ] 后端API（手机号验证、历史同步）
- [ ] 应用图标和截图
- [ ] App Store上架材料

## 开发进度
**2026-03-10**: 项目框架搭建，基础UI完成，Vision OCR集成

## 下一步
1. 完善Word导出功能
2. 集成StoreKit
3. 连接后端服务
