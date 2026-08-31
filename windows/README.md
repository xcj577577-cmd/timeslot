# 时隙 for Windows — 核心内核（M1）

macOS 版时隙的 Windows 移植，当前完成**核心内核**：数据模型、备份读写、倒计时/番茄钟/统计规则。UI（M2）尚未开始。方案与里程碑见 [../docs/windows/PORT_PLAN.md](../docs/windows/PORT_PLAN.md)。

## 结构

| 项目 | 内容 |
| --- | --- |
| `TimeSlotCore` | 备份 JSON 契约（Apple 纪元日期、schemaVersion 1）、倒计时数学、番茄钟引擎、Asia/Shanghai 周统计 |
| `TimeSlotCore.Tests` | 15 项测试：与 macOS 端对拍的契约测试（同一 fixture）+ 规则测试 |
| `TimeSlotCli` | `validate` 命令：校验 macOS 导出的备份并输出摘要 |

## 本机构建（任意平台）

```bash
dotnet test TimeSlot.sln
dotnet run --project TimeSlotCli -- validate ../docs/windows/fixtures/sample-backup-v1.json
```

## 双端一致性

- 数据契约：[../docs/windows/DATA_FORMAT.md](../docs/windows/DATA_FORMAT.md)，fixture 为 [../docs/windows/fixtures/sample-backup-v1.json](../docs/windows/fixtures/sample-backup-v1.json)。
- macOS 端契约测试：`Tests/CountdownWidgetTests/WindowsBackupContractTests.swift`。
- 已验证：Swift `JSONEncoder`（与 app 导出备份同配置）编码的字节流可被 `TimeSlotCore` 解码且语义正确。
- CI：`windows-latest` 跑本目录测试（见 [.github/workflows/ci.yml](../.github/workflows/ci.yml) 的 `windows-core` job）。

## 核心行为约定（与 macOS 版对齐）

- 倒计时：暂停冻结剩余（`pausedRemaining`），运行中按目标时刻推算；进度钳制到 0–1。
- 番茄钟：运行剩余按绝对结束时刻计算；每 N 轮专注进长休；「停止」入账、「重置」不入账。
- 统计：日期边界一律 Asia/Shanghai；周为周一至周日；跨午夜记录按实际时间拆分归属日期；只有 `focus` 阶段计入专注统计。
- 备份：≤ 20MB；`schemaVersion` 必须为 1。

## 在 Windows 设备上接手

1. **装环境**：Windows 11 优先（M3 桌面小组件依赖置顶窗口行为）。
   - Visual Studio 2022 Community + 「WinUI 应用程序开发」工作负载（含 Windows App SDK 与 Win11 SDK）
   - Git for Windows；.NET 8 SDK 随 VS 安装
2. **克隆并过环境门**：`git clone https://github.com/xcj577577-cmd/timeslot.git`，然后：

   ```powershell
   cd timeslot\windows
   dotnet test TimeSlot.sln
   ```

   15 项测试全绿即环境就绪。这一步不写任何 UI 代码前先做。
3. **用真实备份做冒烟**（可选）：在 macOS 时隙「设置 → 备份」导出 JSON，拷到 Windows 后 `dotnet run --project TimeSlotCli -- validate <备份.json>`，确认真实数据可读。
4. **开始 M2**：按 [../docs/windows/PORT_PLAN.md](../docs/windows/PORT_PLAN.md) 加 WinUI 3 项目到本解决方案；graphite 配色参考 macOS 端 `Sources/CountdownWidget/DesignTokens.swift`，行为以 `TimeSlotCore` 测试为规格。
5. **推送习惯**：任何 push 都会触发 CI（Swift tests + Windows core tests），红了对拍修复即可，Windows 侧有免费安全网。
