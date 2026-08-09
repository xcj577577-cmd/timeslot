# 时隙

把倒计时与番茄钟固定在 Mac 桌面上的专注工具。

时隙不是悬浮窗，而是使用 macOS WidgetKit 的桌面小组件，和天气、日历一样驻留在桌面层，可长期保留、自动同步。所有时间均按北京时间（Asia/Shanghai）计算。

## 功能

- **倒计时**：为考试、发布、纪念日等任意目标设置倒计时，支持暂停、继续、编辑与桌面小组件固定显示；到达目标时本地通知提醒。
- **番茄钟**：专注 / 短休息 / 长休息自动流转，支持预设节奏、任务管理与阶段记录。
- **正计时**：从零累计的自由计时，停止后按当前任务记入专注统计。
- **专注统计**：阶段记录、按天专注趋势、按任务分布，支持全部 / 今天 / 近 7 天 / 本月 / 自定义日期范围。
- **桌面小组件**：倒计时、正计时、番茄钟、周目标与组合版；应用内任何变化自动同步，小组件 45 秒自刷新兜底。
- **外观与配色**：跟随系统 / 浅色 / 深色三种外观模式，青绿、珊瑚、靛蓝、紫罗兰、石墨 5 套颜色预设（每套内置深浅双档）。
- **本地通知**：倒计时到达、番茄钟阶段结束时提醒（首次使用时按系统提示授权）。
- **键盘操作**：⌘1 倒计时、⌘2 番茄钟、⌘N 新建倒计时。
- **设置与备份**：设置页可开关通知提醒与提示音、调整外观与配色、调整番茄钟节奏；支持一键导出 / 导入全部数据备份。
- **防误删**：删除倒计时前二次确认。

## 系统要求

- macOS 14 Sonoma 或更新版本
- Apple Silicon 或 Intel Mac（通用二进制）

## 构建

```bash
# Release 构建（含桌面小组件扩展）
xcodebuild -project CountdownWidget.xcodeproj -scheme CountdownWidget \
  -configuration Release -derivedDataPath /tmp/xianz-build build

# 运行测试
swift test --disable-sandbox
```

构建产物位于 `/tmp/xianz-build/Build/Products/Release/时隙.app`。

## 安装

1. 从 [Releases](../../releases) 下载 `时隙-macOS.zip`，解压后把 `时隙.app` 拖入「应用程序」。
2. 首次打开如被 Gatekeeper 拦截：右键「时隙.app」→ 打开 → 确认；或 `xattr -d com.apple.quarantine /Applications/时隙.app`。
3. 在桌面空白处右键「编辑小组件」，搜索「时隙」，添加倒计时、正计时、番茄钟或周目标小组件。

## 目录结构

- `Sources/CountdownWidget/`：主应用源码（界面、模型、状态与通知）。
- `WidgetExtension/`：桌面小组件扩展。
- `Tests/`：核心逻辑测试。
- `AppBundle/`：Info.plist 与沙盒授权。
- `outputs/`：发布资产（zip、发布说明、品牌文件与文档）。

## 隐私

时隙不联网、不收集数据、不要求账号。所有数据只保存在本机，且受 App Sandbox 保护。
