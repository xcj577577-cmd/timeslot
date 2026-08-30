# 时隙备份文件格式（schemaVersion 1）

本文档是时隙导出备份（`导出备份` 生成的 `.json`）的完整数据契约。任何平台实现这份契约，即可读取 macOS 版时隙的备份，并生成可被 macOS 版导入的文件。

## 总体规则

- UTF-8 JSON，`prettyPrinted` + `sortedKeys`（键序不敏感，读端按键名取值）。
- **日期编码为 Apple 参考纪元秒**：`Double`，自 `2001-01-01T00:00:00Z` 起的秒数（Swift `JSONEncoder` 默认策略）。换算：`Unix 秒 = Apple 秒 + 978307200`。
- UUID 一律小写字符串。
- 时长/间隔字段单位为秒（`TimeInterval`，Double）。
- 文件大小上限 20 MB（`BackupValidationPolicy.maximumFileSize`）。
- 颜色为 `#RRGGBB` 十六进制字符串。

## 顶层结构

```json
{
  "schemaVersion": 1,
  "items":               [ CountdownItem ],
  "pomodoro":            PomodoroState,
  "history":             [ PomodoroSessionRecord ],
  "tasks":               [ PomodoroTask ],
  "displayMode":         String,
  "timeUnit":            String,
  "exportedAt":          日期
}
```

## CountdownItem

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | UUID | |
| `title` | String | 已归一化的标题 |
| `targetDate` | 日期 | 目标时刻 |
| `colorHex` | String | `#RRGGBB`，默认 `#2C8C7C` |
| `isPinned` | Bool | 是否固定目标 |
| `createdAt` | 日期 | 创建时刻 |
| `totalDuration` | Double | 总周期秒数，≥ 1 |
| `pausedRemaining` | Double? | 暂停时的剩余秒数；`null` 表示运行中 |

进度 = `(totalDuration - 剩余) / totalDuration`；剩余 = 暂停时取 `pausedRemaining`，运行中取 `targetDate - now`。

## PomodoroTask

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | UUID | |
| `title` | String | ≤ 40 字符 |
| `createdAt` | 日期 | 缺失时按导出时刻补齐 |
| `colorHex` | String | `""` 表示未分配（旧数据），读端需容忍 |

## PomodoroSessionRecord

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | UUID | |
| `phase` | String | `focus` / `shortBreak` / `longBreak` |
| `taskTitle` | String | 记录归属的任务名 |
| `plannedDuration` | Double | 计划时长（秒） |
| `actualDuration` | Double | 实际时长（秒） |
| `startedAt` / `endedAt` | 日期 | 起止时刻；跨午夜按实际时间归属日期 |
| `status` | String | `completed` / `skipped` / `interrupted` / `stopped` / `stopwatch` |

专注统计只累计 `phase == "focus"` 的记录；周边界按 Asia/Shanghai 的周一至周日。

## PomodoroState

全部字段可缺省（`decodeIfPresent` + 默认值），读端应同样容忍：

| 字段 | 类型 | 默认 |
| --- | --- | --- |
| `taskTitle` | String | `专注当前任务` |
| `phase` | String | `focus` |
| `focusMinutes` | Int | 25 |
| `shortBreakMinutes` | Int | 5 |
| `longBreakMinutes` | Int | 15 |
| `roundsBeforeLongBreak` | Int | 4 |
| `weeklyFocusGoalMinutes` | Int | 600 |
| `completedFocusSessions` | Int | 0 |
| `isRunning` | Bool | false |
| `endDate` | 日期? | null |
| `pausedRemaining` | Double | 1500 |
| `sessionStartedAt` / `activeStartedAt` | 日期? | null |
| `accumulatedElapsed` | Double | 0 |
| `stopwatchRunning` | Bool | false |
| `stopwatchSessionStartedAt` / `stopwatchActiveStartedAt` | 日期? | null |
| `stopwatchAccumulated` | Double | 0 |

## 顶层杂项

- `displayMode`: String，`countdown` / `pomodoro` / `both`（小组件显示模式）。
- `timeUnit`: String，默认 `"auto"`（小组件计时单位）。
- `exportedAt`: 日期。

## 导入语义（macOS 端行为，跨平台实现应保持一致）

1. 导入前强制把当前数据完整备份到 `~/Library/Application Support/时隙/AutomaticBackups/导入前自动备份-<时间戳>-<随机后缀>.json`；自动备份失败则中止导入。
2. 导入会覆盖现有倒计时、历史、任务与显示设置。

## 跨平台兼容的最小实现集

只做到数据互通时，Windows 端至少需要正确处理：`items`（含暂停语义）、`history`（含时区周边界）、`tasks`、`pomodoro.weeklyFocusGoalMinutes`，以及 Apple 纪元日期换算。其余字段可原样保留以便回传。
