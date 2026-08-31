using TimeSlot.Core;
using Xunit;

namespace TimeSlotCore.Tests;

/// <summary>
/// Windows 兼容契约：docs/windows/DATA_FORMAT.md 的 fixture 必须被 C# 端解码，
/// 与 macOS 端 WindowsBackupContractTests 对拍。
/// </summary>
public class BackupContractTests
{
    private static string FixturePath(string name)
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null &&
               !Directory.Exists(Path.Combine(dir.FullName, "docs", "windows", "fixtures")))
        {
            dir = dir.Parent!;
        }
        Assert.NotNull(dir);
        return Path.Combine(dir!.FullName, "docs", "windows", "fixtures", name);
    }

    private static BackupPayload DecodeSample()
        => BackupCodec.Decode(File.ReadAllBytes(FixturePath("sample-backup-v1.json")));

    [Fact]
    public void SampleBackupV1_DecodesWithContractFields()
    {
        var payload = DecodeSample();

        Assert.Equal(BackupPayload.CurrentSchemaVersion, payload.SchemaVersion);
        Assert.Equal(2, payload.Items.Count);
        Assert.Equal(2, payload.History.Count);
        Assert.Equal(2, payload.Tasks.Count);
        Assert.Equal("both", payload.DisplayMode);
        Assert.Equal("auto", payload.TimeUnit);
        Assert.Equal(AppleEpoch.FromAppleSeconds(800_000_000), payload.ExportedAt);
    }

    [Fact]
    public void CountdownPauseSemantics_SurviveRoundTrip()
    {
        var payload = DecodeSample();

        var running = Assert.Single(payload.Items, i => i.PausedRemaining is null);
        Assert.Equal("项目上线", running.Title);
        Assert.Equal("#2C8C7C", running.ColorHex);
        Assert.True(running.IsPinned);

        var paused = Assert.Single(payload.Items, i => i.PausedRemaining is not null);
        Assert.Equal(123456.5, paused.PausedRemaining);
        Assert.False(paused.IsPinned);

        // 重新编码后再解码，核心字段不丢
        var again = BackupCodec.Decode(BackupCodec.Encode(payload));
        Assert.Equal(payload.Items[0].Title, again.Items[0].Title);
        Assert.Equal(payload.Items[0].TargetDate, again.Items[0].TargetDate);
        Assert.Equal(payload.Items[1].PausedRemaining, again.Items[1].PausedRemaining);
        Assert.Equal(payload.ExportedAt, again.ExportedAt);
    }

    [Fact]
    public void HistoryPhaseAndStatus_MatchContract()
    {
        var payload = DecodeSample();

        Assert.Contains(payload.History,
            h => h.Phase == PomodoroPhase.Focus && h.Status == PomodoroRecordStatus.Completed
                 && h.TaskTitle == "写作");
        Assert.Contains(payload.History, h => h.Status == PomodoroRecordStatus.Stopwatch);
    }

    [Fact]
    public void PomodoroState_ToleratesPartialPayload()
    {
        var payload = DecodeSample();

        // fixture 只写入了部分字段，其余必须回退到默认值
        Assert.Equal("写作", payload.Pomodoro.TaskTitle);
        Assert.Equal(600, payload.Pomodoro.WeeklyFocusGoalMinutes);
        Assert.Equal(5, payload.Pomodoro.ShortBreakMinutes);
        Assert.False(payload.Pomodoro.IsRunning);
    }

    [Fact]
    public void AppleReferenceEpoch_MatchesDocumentation()
    {
        // DATA_FORMAT.md：Unix 秒 = Apple 秒 + 978307200
        const double apple = 800_000_000;
        Assert.Equal(apple + 978_307_200,
            AppleEpoch.FromAppleSeconds(apple).ToUnixTimeSeconds(), precision: 0);
    }

    [Fact]
    public void Decode_RejectsWrongSchemaAndOversize()
    {
        var bad = System.Text.Encoding.UTF8.GetBytes("{\"schemaVersion\":2,\"items\":[]}");
        var e = Assert.Throws<BackupValidationException>(() => BackupCodec.Decode(bad));
        Assert.Equal("unsupportedSchema", e.Code);

        Assert.Throws<BackupValidationException>(
            () => BackupCodec.Decode(new byte[BackupCodec.MaxFileSize + 1]));
    }
}
