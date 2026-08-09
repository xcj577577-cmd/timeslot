#!/usr/bin/env swift

import AppKit
import Foundation

struct RenderJob {
    let source: URL
    let destination: URL
    let width: Int
    let height: Int
}

enum RenderError: Error {
    case cannotLoad(URL)
    case cannotCreateBitmap(Int, Int)
    case cannotCreateContext
    case cannotEncodePNG(URL)
}

func render(_ job: RenderJob) throws {
    guard let image = NSImage(contentsOf: job.source) else {
        throw RenderError.cannotLoad(job.source)
    }
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: job.width,
        pixelsHigh: job.height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw RenderError.cannotCreateBitmap(job.width, job.height)
    }
    bitmap.size = NSSize(width: job.width, height: job.height)

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw RenderError.cannotCreateContext
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = true
    context.imageInterpolation = NSImageInterpolation.high
    let bounds = NSRect(x: 0, y: 0, width: job.width, height: job.height)
    NSColor.clear.setFill()
    bounds.fill()
    image.draw(
        in: bounds,
        from: NSRect(origin: .zero, size: image.size),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(
        using: NSBitmapImageRep.FileType.png,
        properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 1.0]
    ) else {
        throw RenderError.cannotEncodePNG(job.destination)
    }
    try FileManager.default.createDirectory(
        at: job.destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: job.destination, options: Data.WritingOptions.atomic)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let mark = root.appendingPathComponent("outputs/时隙-logo-v3.svg")
let horizontal = root.appendingPathComponent("outputs/时隙-logo-v3-横向.svg")
let iconDirectory = root.appendingPathComponent(
    "Sources/CountdownWidget/Assets.xcassets/AppIcon.appiconset",
    isDirectory: true
)

var jobs = [
    RenderJob(
        source: mark,
        destination: root.appendingPathComponent("outputs/时隙-logo-v3-错位条带-2048.png"),
        width: 2048,
        height: 2048
    ),
    RenderJob(
        source: horizontal,
        destination: root.appendingPathComponent("outputs/时隙-logo-v3-横向-2048.png"),
        width: 4096,
        height: 1536
    )
]

let iconJobs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

jobs.append(contentsOf: iconJobs.map { item in
    RenderJob(
        source: mark,
        destination: iconDirectory.appendingPathComponent(item.name),
        width: item.pixels,
        height: item.pixels
    )
})

for job in jobs {
    try render(job)
}

print("Rendered \(jobs.count) brand assets.")
