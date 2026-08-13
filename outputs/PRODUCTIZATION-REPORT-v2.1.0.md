# 时隙 2.1.0 产品化与小组件修复报告

状态：本机发行候选版完成  
核验日期：2026 年 8 月 9 日

## 问题与根因

桌面小组件消失的直接原因是 `WidgetExtension/CountdownDesktopWidget.entitlements` 被清空，小组件扩展因此失去 App Sandbox 和 App Group 授权。旧崩溃日志中的 `_libsecinit_appsandbox` 与该授权缺失一致。共享容器数据本身没有丢失。

最终回归时还发现：点击桌面小组件唤醒已隐藏的应用会生成第二个主窗口。根因是主界面使用支持多实例的 SwiftUI `WindowGroup`，自定义 URL 被 macOS 视为新场景请求。主场景已改为单实例 `Window("时隙", id: "main")`。

## 本轮处理

1. 恢复主应用与小组件一致的 App Group，并重新启用扩展沙盒。
2. 加固共享状态解码、原子写入、时间线生成和 WidgetKit 刷新策略。
3. 重设计主应用、小组件、编辑器、设置、小组件指南、品牌标识和 AppIcon。
4. 修复空列表样例复活、陈旧通知、计时状态冲突、异常输入和备份覆盖风险。
5. 增加 Privacy Manifest、减少动态效果、辅助功能标签和键盘搜索。
6. 将主窗口改为单实例场景，保留小组件 URL 跳转。
7. 扩充自动化测试并增加可重复执行的发行验证脚本。
8. 更新使用说明、隐私政策、App Store 元数据、检查清单和发行说明。

## 数据核验

- 倒计时：1 个，标题为用户自建目标。
- 番茄钟/专注历史：117 条。
- 升级前后共享容器路径未变。
- 小组件共享状态能读取当前倒计时并正常渲染。

## 验证结果

- `swift test --disable-sandbox`：29 项通过，0 失败。
- Xcode Release：构建成功。
- 主应用与扩展：arm64 + x86_64。
- `codesign --verify --deep --strict`：通过。
- 主应用与扩展：App Sandbox、App Group、Privacy Manifest 均通过脚本校验。
- 网络客户端授权：主应用与扩展均不存在。
- 小组件注册：仅保留 `/Applications/时隙.app` 中的一份。
- macOS 小组件库：全部时隙类型以及小、中、大预览正常。
- 真实桌面小组件：标题、剩余时间和目标日期正常显示。
- 真实点击：回到倒计时页面，主窗口 ID 始终为 `main`，未生成重复窗口。
- ZIP：解包后深度严格签名验证通过。
- DMG：`hdiutil verify` 校验通过。

## 发行候选产物

- `时隙-macOS-v2.1.0-build50.zip`
  - SHA-256：`4e9b981ce5c4b82f15e116f67f0531772b1c27b23046f2e75057de41ccf58b4c`
- `时隙-macOS-v2.1.0-build50.dmg`
  - SHA-256：`280cf5a0ef12ebd0d272e3d3c62d9789c5d2e04f65ea8effa281603564fdf775`

## 备份与回滚

本机保留了基线源码备份和安装前应用/数据备份，路径不纳入公开仓库。

## 公开发布前剩余事项

当前电脑只有 Apple Development 签名身份，适合本机开发与验证，不等同于公开分发签名。正式发布还需完成以下任一流程：

- Mac App Store：App Store Distribution 签名、归档上传、商店审核。
- 站外分发：Developer ID Application 签名、Apple 公证、stapler 附加票据。

此外还需提供公开的支持 URL、隐私政策 URL、支持邮箱，并使用干净示例数据制作商店截图。
