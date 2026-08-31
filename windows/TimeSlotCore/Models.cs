using System.Text.Json;
using System.Text.Json.Serialization;

namespace TimeSlot.Core;

/// <summary>Apple 参考纪元（2001-01-01T00:00:00Z）秒 与 DateTimeOffset 的换算。</summary>
public static class AppleEpoch
{
    public static readonly DateTimeOffset Epoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);

    /// <summary>Unix 秒 = Apple 秒 + 978307200（与 docs/windows/DATA_FORMAT.md 一致）。</summary>
    public const double UnixOffsetSeconds = 978307200;

    public static DateTimeOffset FromAppleSeconds(double seconds) => Epoch.AddSeconds(seconds);

    public static double ToAppleSeconds(DateTimeOffset instant) => (instant - Epoch).TotalSeconds;
}

public sealed class AppleEpochConverter : JsonConverter<DateTimeOffset>
{
    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        return reader.TokenType == JsonTokenType.Number
            ? AppleEpoch.FromAppleSeconds(reader.GetDouble())
            : throw new JsonException("备份中的日期必须是 Apple 参考纪元秒（数字）。");
    }

    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options)
        => writer.WriteNumberValue(AppleEpoch.ToAppleSeconds(value));
}

public static class BackupJson
{
    public static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        NumberHandling = JsonNumberHandling.AllowReadingFromString,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        Converters =
        {
            new AppleEpochConverter(),
            new JsonStringEnumConverter(JsonNamingPolicy.CamelCase, allowIntegerValues: false),
        },
    };
}

public enum PomodoroPhase
{
    Focus,
    ShortBreak,
    LongBreak,
}

public enum PomodoroRecordStatus
{
    Completed,
    Skipped,
    Interrupted,
    Stopped,
    Stopwatch,
}

public sealed class CountdownItem
{
    [JsonPropertyName("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    [JsonPropertyName("title")]
    public string Title { get; set; } = "";

    [JsonPropertyName("targetDate")]
    public DateTimeOffset TargetDate { get; set; }

    [JsonPropertyName("colorHex")]
    public string ColorHex { get; set; } = "#2C8C7C";

    [JsonPropertyName("isPinned")]
    public bool IsPinned { get; set; }

    [JsonPropertyName("createdAt")]
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    [JsonPropertyName("totalDuration")]
    public double TotalDuration { get; set; } = 1;

    /// <summary>暂停时的剩余秒数；null 表示运行中。</summary>
    [JsonPropertyName("pausedRemaining")]
    public double? PausedRemaining { get; set; }
}

public sealed class PomodoroTask
{
    [JsonPropertyName("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    [JsonPropertyName("title")]
    public string Title { get; set; } = "";

    [JsonPropertyName("createdAt")]
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    /// <summary>空串代表尚未分配颜色（旧数据），读端需容忍。</summary>
    [JsonPropertyName("colorHex")]
    public string ColorHex { get; set; } = "";
}

public sealed class PomodoroSessionRecord
{
    [JsonPropertyName("id")]
    public Guid Id { get; set; } = Guid.NewGuid();

    [JsonPropertyName("phase")]
    public PomodoroPhase Phase { get; set; } = PomodoroPhase.Focus;

    [JsonPropertyName("taskTitle")]
    public string TaskTitle { get; set; } = "";

    [JsonPropertyName("plannedDuration")]
    public double PlannedDuration { get; set; }

    [JsonPropertyName("actualDuration")]
    public double ActualDuration { get; set; }

    [JsonPropertyName("startedAt")]
    public DateTimeOffset StartedAt { get; set; }

    [JsonPropertyName("endedAt")]
    public DateTimeOffset EndedAt { get; set; }

    [JsonPropertyName("status")]
    public PomodoroRecordStatus Status { get; set; } = PomodoroRecordStatus.Completed;
}

public sealed class PomodoroState
{
    [JsonPropertyName("taskTitle")]
    public string TaskTitle { get; set; } = "专注当前任务";

    [JsonPropertyName("phase")]
    public PomodoroPhase Phase { get; set; } = PomodoroPhase.Focus;

    [JsonPropertyName("focusMinutes")]
    public int FocusMinutes { get; set; } = 25;

    [JsonPropertyName("shortBreakMinutes")]
    public int ShortBreakMinutes { get; set; } = 5;

    [JsonPropertyName("longBreakMinutes")]
    public int LongBreakMinutes { get; set; } = 15;

    [JsonPropertyName("roundsBeforeLongBreak")]
    public int RoundsBeforeLongBreak { get; set; } = 4;

    /// <summary>每周专注目标，分钟。</summary>
    [JsonPropertyName("weeklyFocusGoalMinutes")]
    public int WeeklyFocusGoalMinutes { get; set; } = 600;

    [JsonPropertyName("completedFocusSessions")]
    public int CompletedFocusSessions { get; set; }

    [JsonPropertyName("isRunning")]
    public bool IsRunning { get; set; }

    [JsonPropertyName("endDate")]
    public DateTimeOffset? EndDate { get; set; }

    [JsonPropertyName("pausedRemaining")]
    public double PausedRemaining { get; set; } = 25 * 60;

    [JsonPropertyName("sessionStartedAt")]
    public DateTimeOffset? SessionStartedAt { get; set; }

    [JsonPropertyName("activeStartedAt")]
    public DateTimeOffset? ActiveStartedAt { get; set; }

    [JsonPropertyName("accumulatedElapsed")]
    public double AccumulatedElapsed { get; set; }

    [JsonPropertyName("stopwatchRunning")]
    public bool StopwatchRunning { get; set; }

    [JsonPropertyName("stopwatchSessionStartedAt")]
    public DateTimeOffset? StopwatchSessionStartedAt { get; set; }

    [JsonPropertyName("stopwatchActiveStartedAt")]
    public DateTimeOffset? StopwatchActiveStartedAt { get; set; }

    [JsonPropertyName("stopwatchAccumulated")]
    public double StopwatchAccumulated { get; set; }
}

public sealed class BackupPayload
{
    public const int CurrentSchemaVersion = 1;

    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion { get; set; } = CurrentSchemaVersion;

    [JsonPropertyName("items")]
    public List<CountdownItem> Items { get; set; } = [];

    [JsonPropertyName("pomodoro")]
    public PomodoroState Pomodoro { get; set; } = new();

    [JsonPropertyName("history")]
    public List<PomodoroSessionRecord> History { get; set; } = [];

    [JsonPropertyName("tasks")]
    public List<PomodoroTask> Tasks { get; set; } = [];

    [JsonPropertyName("displayMode")]
    public string DisplayMode { get; set; } = "both";

    [JsonPropertyName("timeUnit")]
    public string TimeUnit { get; set; } = "auto";

    [JsonPropertyName("exportedAt")]
    public DateTimeOffset ExportedAt { get; set; } = DateTimeOffset.UtcNow;
}
