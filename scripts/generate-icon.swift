#!/usr/bin/env swift

import AppKit
import Foundation

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let projectURL = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let outputURL = projectURL
    .appending(path: "Rewrite/Resources/Assets.xcassets/AppIcon.appiconset")

let outputs: [(String, Int)] = [
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

func icon(size: Int) -> Data {
    let dimension = CGFloat(size)
    guard
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: representation)
    else {
        fatalError("Unable to create app icon bitmap")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    context.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: dimension, height: dimension).fill()

    let inset = dimension * 0.045
    let tile = NSRect(
        x: inset,
        y: inset,
        width: dimension - (inset * 2),
        height: dimension - (inset * 2)
    )
    let tilePath = NSBezierPath(
        roundedRect: tile,
        xRadius: dimension * 0.22,
        yRadius: dimension * 0.22
    )

    let gradient = NSGradient(colors: [
        NSColor(red: 0.12, green: 0.47, blue: 0.98, alpha: 1),
        NSColor(red: 0.39, green: 0.30, blue: 0.95, alpha: 1)
    ])!
    gradient.draw(in: tilePath, angle: -42)

    // Same glyph as the menu bar icon (character.cursor.ibeam) so the Dock
    // tile and menu bar read as one mark.
    guard
        let baseSymbol = NSImage(
            systemSymbolName: "character.cursor.ibeam",
            accessibilityDescription: nil
        ),
        let symbol = baseSymbol.withSymbolConfiguration(
            .init(pointSize: dimension * 0.52, weight: .bold)
        )
    else {
        fatalError("Unable to load character.cursor.ibeam symbol")
    }
    symbol.isTemplate = true

    let symbolSize = symbol.size
    let whiteSymbol = NSImage(size: symbolSize, flipped: false) { rect in
        NSColor.white.setFill()
        rect.fill()
        symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
        return true
    }
    whiteSymbol.draw(
        at: NSPoint(
            x: (dimension - symbolSize.width) / 2,
            y: (dimension - symbolSize.height) / 2
        ),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )

    context.flushGraphics()

    guard let png = representation.representation(using: .png, properties: [:]) else {
        fatalError("Unable to render app icon")
    }
    return png
}

try FileManager.default.createDirectory(
    at: outputURL,
    withIntermediateDirectories: true
)

for (filename, size) in outputs {
    try icon(size: size).write(to: outputURL.appending(path: filename))
}

print("Generated \(outputs.count) app icon files")
