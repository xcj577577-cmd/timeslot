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
