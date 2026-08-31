using System.Text.Json;

namespace TimeSlot.Core;

/// <summary>备份读写：20MB 上限、schemaVersion 校验、Apple 纪元日期。</summary>
public static class BackupCodec
{
    public const int MaxFileSize = 20 * 1024 * 1024;

    public static BackupPayload Decode(byte[] data)
    {
        if (data.Length > MaxFileSize)
            throw new BackupValidationException("fileTooLarge",
                $"备份超过 {MaxFileSize / 1024 / 1024} MB 上限。");
        BackupPayload payload;
        try
        {
            payload = JsonSerializer.Deserialize<BackupPayload>(data, BackupJson.Options)
                      ?? throw new BackupValidationException("empty", "备份内容为空。");
        }
        catch (JsonException e)
        {
            throw new BackupValidationException("invalidJson", e.Message);
        }
        if (payload.SchemaVersion != BackupPayload.CurrentSchemaVersion)
            throw new BackupValidationException("unsupportedSchema",
                $"schemaVersion {payload.SchemaVersion} 不受支持，预期 {BackupPayload.CurrentSchemaVersion}。");
        return payload;
    }

    public static byte[] Encode(BackupPayload payload)
        => JsonSerializer.SerializeToUtf8Bytes(payload, BackupJson.Options);
}

public sealed class BackupValidationException(string code, string message)
    : Exception(message)
{
    public string Code { get; } = code;
}
