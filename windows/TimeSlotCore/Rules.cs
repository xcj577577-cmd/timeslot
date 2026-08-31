using System.Text.Json;

namespace TimeSlot.Core;

/// <summary>倒计时数学：剩余、进度、暂停语义（与 macOS 版 CountdownItem 一致）。</summary>
public static class CountdownMath
{
    /// <summary>剩余秒数：暂停时冻结为 pausedRemaining，运行中为 targetDate - now。</summary>
    public static double RemainingSeconds(CountdownItem item, DateTimeOffset now)
        => item.PausedRemaining ?? (item.TargetDate - now).TotalSeconds;

    /// <summary>进度 0..1 = (totalDuration - 剩余) / totalDuration。</summary>
    public static double Progress(CountdownItem item, DateTimeOffset now)
    {
        if (item.TotalDuration <= 0) return 0;
        var progress = (item.TotalDuration - RemainingSeconds(item, now)) / item.TotalDuration;
        return Math.Clamp(progress, 0, 1);
    }
}

/// <summary>番茄钟规则：阶段流转、运行剩余、停止入账（与 macOS 版行为对齐）。</summary>
public static class PomodoroEngine
{
    /// <summary>运行中的剩余秒数按绝对结束时刻计算（endDate - now）。</summary>
    public static double RemainingSeconds(PomodoroState state, DateTimeOffset now)
    {
        if (!state.IsRunning || state.EndDate is null) return state.PausedRemaining;
        return Math.Max(0, (state.EndDate.Value - now).TotalSeconds);
    }

    /// <summary>完成一个专注阶段后调用：累计轮数并给出下一阶段。</summary>
    public static PomodoroPhase AdvanceAfterFocus(PomodoroState state)
    {
        state.CompletedFocusSessions += 1;
        return state.CompletedFocusSessions % Math.Max(1, state.RoundsBeforeLongBreak) == 0
            ? PomodoroPhase.LongBreak
            : PomodoroPhase.ShortBreak;
    }

    /// <summary>阶段时长（秒）。</summary>
    public static double PhaseSeconds(PomodoroState state, PomodoroPhase phase) => phase switch
    {
        PomodoroPhase.Focus => state.FocusMinutes * 60.0,
        PomodoroPhase.ShortBreak => state.ShortBreakMinutes * 60.0,
        PomodoroPhase.LongBreak => state.LongBreakMinutes * 60.0,
        _ => throw new ArgumentOutOfRangeException(nameof(phase)),
    };

    /// <summary>「停止」会把当前阶段按实际时长写入记录（「重置」不入账）。</summary>
    public static PomodoroSessionRecord BuildStoppedRecord(
        PomodoroState state, PomodoroPhase phase, string taskTitle,
        DateTimeOffset startedAt, DateTimeOffset endedAt, double actualSeconds)
        => new()
        {
            Phase = phase,
            TaskTitle = taskTitle,
            PlannedDuration = PhaseSeconds(state, phase),
            ActualDuration = Math.Max(0, actualSeconds),
            StartedAt = startedAt,
            EndedAt = endedAt,
            Status = PomodoroRecordStatus.Stopped,
        };
}

/// <summary>专注统计：一切日期按 Asia/Shanghai，周为周一至周日，跨午夜记录按实际时间拆分归属。</summary>
public static class WeeklyStats
{
    public static TimeZoneInfo ShanghaiTimeZone() =>
        TimeZoneInfo.FindSystemTimeZoneById(
            TimeZoneInfo.GetSystemTimeZones().Any(t => t.Id == "Asia/Shanghai")
                ? "Asia/Shanghai"
                : "China Standard Time");

    /// <summary>该时刻所在本地日期（时区归一）。</summary>
    public static DateOnly LocalDate(DateTimeOffset instant, TimeZoneInfo tz)
        => DateOnly.FromDateTime(instant.ToOffset(tz.GetUtcOffset(instant)).DateTime);

    /// <summary>本地周起点（周一 00:00）对应的本地日期。</summary>
    public static DateOnly StartOfLocalWeek(DateOnly localDate)
    {
        // DateOnly.DayOfWeek: Sunday=0 ... Saturday=6；周一为一周起点
        var back = ((int)localDate.DayOfWeek + 6) % 7;
        return localDate.AddDays(-back);
    }

    /// <summary>
    /// 按本地日累计专注分钟。跨午夜记录按 [startedAt, endedAt] 与各本地日的交集拆分，
    /// 只统计 focus 阶段。
    /// </summary>
    public static SortedDictionary<DateOnly, double> FocusMinutesByLocalDay(
        IEnumerable<PomodoroSessionRecord> records, TimeZoneInfo tz)
    {
        var result = new SortedDictionary<DateOnly, double>();
        foreach (var record in records)
        {
            if (record.Phase != PomodoroPhase.Focus) continue;
            if (record.ActualDuration <= 0) continue;
            var end = record.EndedAt < record.StartedAt ? record.StartedAt : record.EndedAt;

            var day = LocalDate(record.StartedAt, tz);
            while (true)
            {
                var dayStartLocal = day.ToDateTime(TimeOnly.MinValue);
                var dayStart = ToInstant(day, tz);
                var dayEnd = ToInstant(day.AddDays(1), tz);
                if (dayStart >= end) break;

                var overlapStart = record.StartedAt > dayStart ? record.StartedAt : dayStart;
                var overlapEnd = end < dayEnd ? end : dayEnd;
                if (overlapEnd > overlapStart)
                {
                    var minutes = (overlapEnd - overlapStart).TotalMinutes;
                    result[day] = result.GetValueOrDefault(day) + minutes;
                }
                day = day.AddDays(1);
                _ = dayStartLocal;
            }
        }
        return result;
    }

    /// <summary>某一周（含 givenDay 的周一至周日）的专注总分钟。</summary>
    public static double FocusMinutesForWeek(
        IEnumerable<PomodoroSessionRecord> records, TimeZoneInfo tz, DateOnly anyDayInWeek)
    {
        var start = StartOfLocalWeek(anyDayInWeek);
        var end = start.AddDays(7);
        return FocusMinutesByLocalDay(records, tz)
            .Where(kv => kv.Key >= start && kv.Key < end)
            .Sum(kv => kv.Value);
    }

    private static DateTimeOffset ToInstant(DateOnly localDate, TimeZoneInfo tz)
    {
        var local = localDate.ToDateTime(TimeOnly.MinValue);
        var offset = tz.GetUtcOffset(local);
        return new DateTimeOffset(local, offset);
    }
}
