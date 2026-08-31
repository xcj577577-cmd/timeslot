using TimeSlot.Core;
using Xunit;

namespace TimeSlotCore.Tests;

public class CountdownMathTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 31, 0, 0, 0, TimeSpan.Zero);

    [Fact]
    public void RunningItem_UsesTargetDateForRemaining()
    {
        var item = new CountdownItem
        {
            Title = "项目上线",
            TargetDate = Now.AddSeconds(86_400),
            TotalDuration = 172_800,
            PausedRemaining = null,
        };
        Assert.Equal(86_400, CountdownMath.RemainingSeconds(item, Now), precision: 0);
        Assert.Equal(0.5, CountdownMath.Progress(item, Now), precision: 6);
    }

    [Fact]
    public void PausedItem_FreezesRemaining()
    {
        var item = new CountdownItem
        {
            Title = "旅行出发",
            TargetDate = Now.AddSeconds(86_400),
            TotalDuration = 172_800,
            PausedRemaining = 43_200,
        };
        Assert.Equal(43_200, CountdownMath.RemainingSeconds(item, Now), precision: 0);
        Assert.Equal(0.75, CountdownMath.Progress(item, Now), precision: 6);
    }

    [Fact]
    public void PastTarget_ClampsProgressToOne()
    {
        var item = new CountdownItem
        {
            Title = "已到达",
            TargetDate = Now.AddSeconds(-100),
            TotalDuration = 100,
        };
        Assert.Equal(1, CountdownMath.Progress(item, Now), precision: 6);
    }
}

public class PomodoroEngineTests
{
    [Fact]
    public void AdvanceAfterFocus_EntersLongBreakEveryNthRound()
    {
        var state = new PomodoroState { RoundsBeforeLongBreak = 4 };
        var expected = new[]
        {
            PomodoroPhase.ShortBreak, PomodoroPhase.ShortBreak,
            PomodoroPhase.ShortBreak, PomodoroPhase.LongBreak,
        };
        foreach (var phase in expected)
        {
            Assert.Equal(phase, PomodoroEngine.AdvanceAfterFocus(state));
            // 休息后回到专注
            state.Phase = PomodoroPhase.Focus;
        }
        Assert.Equal(4, state.CompletedFocusSessions);
    }

    [Fact]
    public void RunningRemaining_UsesAbsoluteEndDate()
    {
        // 对齐 macOS 端 testRunningPomodoroRemainingUsesAbsoluteEndDate
        var start = DateTimeOffset.FromUnixTimeSeconds(1_000_000);
        var state = new PomodoroState
        {
            FocusMinutes = 25,
            Phase = PomodoroPhase.Focus,
            IsRunning = true,
            ActiveStartedAt = start,
            SessionStartedAt = start,
            EndDate = start.AddSeconds(25 * 60),
        };
        var mid = start.AddSeconds(10 * 60);
        Assert.Equal(15 * 60.0, PomodoroEngine.RemainingSeconds(state, mid), precision: 0);
    }

    [Fact]
    public void StoppedRecord_CarriesPlannedAndActual()
    {
        var state = new PomodoroState { FocusMinutes = 25 };
        var start = DateTimeOffset.FromUnixTimeSeconds(1_000_000);
        var record = PomodoroEngine.BuildStoppedRecord(
            state, PomodoroPhase.Focus, "写作",
            start, start.AddSeconds(600), 600);
        Assert.Equal(1500, record.PlannedDuration, precision: 0);
        Assert.Equal(600, record.ActualDuration, precision: 0);
        Assert.Equal(PomodoroRecordStatus.Stopped, record.Status);
    }
}

public class WeeklyStatsTests
{
    private static readonly TimeZoneInfo Tz = WeeklyStats.ShanghaiTimeZone();

    private static PomodoroSessionRecord Focus(
        DateTimeOffset start, DateTimeOffset end, string task = "写作")
        => new()
        {
            Phase = PomodoroPhase.Focus,
            TaskTitle = task,
            PlannedDuration = (end - start).TotalSeconds,
            ActualDuration = (end - start).TotalSeconds,
            StartedAt = start,
            EndedAt = end,
            Status = PomodoroRecordStatus.Completed,
        };

    [Fact]
    public void CrossMidnightRecord_SplitsAcrossLocalDays()
    {
        // 08-30 23:00 ~ 08-31 01:00 北京时间 → 60 分钟归 8/30，60 分钟归 8/31
        var record = Focus(
            new DateTimeOffset(2026, 8, 30, 15, 0, 0, TimeSpan.Zero),
            new DateTimeOffset(2026, 8, 30, 17, 0, 0, TimeSpan.Zero));

        var byDay = WeeklyStats.FocusMinutesByLocalDay([record], Tz);

        Assert.Equal(2, byDay.Count);
        Assert.Equal(60, byDay[new DateOnly(2026, 8, 30)], precision: 6);
        Assert.Equal(60, byDay[new DateOnly(2026, 8, 31)], precision: 6);
    }

    [Fact]
    public void WeekBoundary_IsMondayToSunday_AsiaShanghai()
    {
        // 2026-08-30 是周日，08-31 是周一：同一条跨午夜记录分属两周
        var records = new List<PomodoroSessionRecord>
        {
            Focus(
                new DateTimeOffset(2026, 8, 30, 15, 0, 0, TimeSpan.Zero),
                new DateTimeOffset(2026, 8, 30, 17, 0, 0, TimeSpan.Zero)),
            Focus(
                new DateTimeOffset(2026, 9, 2, 2, 0, 0, TimeSpan.Zero),
                new DateTimeOffset(2026, 9, 2, 2, 25, 0, TimeSpan.Zero)),
        };

        Assert.Equal(60, WeeklyStats.FocusMinutesForWeek(records, Tz, new DateOnly(2026, 8, 30)),
            precision: 6);
        Assert.Equal(85, WeeklyStats.FocusMinutesForWeek(records, Tz, new DateOnly(2026, 8, 31)),
            precision: 6);
    }

    [Fact]
    public void OnlyFocusPhase_CountsTowardStats()
    {
        var records = new List<PomodoroSessionRecord>
        {
            Focus(
                new DateTimeOffset(2026, 8, 31, 2, 0, 0, TimeSpan.Zero),
                new DateTimeOffset(2026, 8, 31, 2, 30, 0, TimeSpan.Zero)),
            new()
            {
                Phase = PomodoroPhase.ShortBreak,
                TaskTitle = "写作",
                ActualDuration = 1800,
                StartedAt = new DateTimeOffset(2026, 8, 31, 3, 0, 0, TimeSpan.Zero),
                EndedAt = new DateTimeOffset(2026, 8, 31, 3, 30, 0, TimeSpan.Zero),
                Status = PomodoroRecordStatus.Completed,
            },
        };

        var byDay = WeeklyStats.FocusMinutesByLocalDay(records, Tz);
        Assert.Equal(30, byDay[new DateOnly(2026, 8, 31)], precision: 6);
    }
}
