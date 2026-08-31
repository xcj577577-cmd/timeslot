using TimeSlot.Core;

// timeslot-cli validate <backup.json> —— 校验 macOS 时隙备份并输出摘要
if (args.Length != 2 || args[0] != "validate")
{
    Console.Error.WriteLine("用法: timeslot-cli validate <backup.json>");
    return 2;
}

try
{
    var payload = BackupCodec.Decode(File.ReadAllBytes(args[1]));
    var tz = WeeklyStats.ShanghaiTimeZone();
    var now = DateTimeOffset.UtcNow;
    var focusMinutes = payload.History
        .Where(h => h.Phase == PomodoroPhase.Focus)
        .Sum(h => h.ActualDuration) / 60.0;
    var thisWeek = WeeklyStats.FocusMinutesForWeek(
        payload.History, tz, WeeklyStats.LocalDate(now, tz));

    Console.WriteLine($"schemaVersion = {payload.SchemaVersion}");
    Console.WriteLine($"exportedAt    = {payload.ExportedAt:yyyy-MM-dd HH:mm:ss} UTC");
    Console.WriteLine($"倒计时        = {payload.Items.Count} 项（运行中 {payload.Items.Count(i => i.PausedRemaining is null)}）");
    foreach (var item in payload.Items)
    {
        var remaining = CountdownMath.RemainingSeconds(item, now);
        Console.WriteLine(
            $"  - {item.Title}: 剩余 {remaining / 86400.0:F1} 天, 进度 {CountdownMath.Progress(item, now):P0}" +
            (item.PausedRemaining is null ? "" : "（已暂停）"));
    }
    Console.WriteLine($"任务          = {payload.Tasks.Count} 个");
    Console.WriteLine($"专注记录      = {payload.History.Count} 条, 累计 {focusMinutes:F1} 分钟");
    Console.WriteLine($"本周专注      = {thisWeek:F1} / {payload.Pomodoro.WeeklyFocusGoalMinutes} 分钟（Asia/Shanghai）");
    return 0;
}
catch (BackupValidationException e)
{
    Console.Error.WriteLine($"invalid: [{e.Code}] {e.Message}");
    return 1;
}
catch (Exception e)
{
    Console.Error.WriteLine($"error: {e.Message}");
    return 1;
}
