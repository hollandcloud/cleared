#!/usr/bin/env swift
// Draws Cleared's app icon and writes every size the asset catalog needs.
//
//   swift Scripts/make-icon.swift
//
// The icon is drawn in code so it can be regenerated and reviewed like the
// rest of the source: an amber tile — the colour of a held deployment — with
// the check that clears it. The check is drawn here rather than borrowed from
// SF Symbols, which Apple's licence does not allow in an app icon.

import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/Assets.xcassets/AppIcon.appiconset")

/// Draws the icon into a square of `size` pixels.
func draw(size: CGFloat, in context: CGContext) {
    let unit = size / 1024
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))

    // The macOS icon grid: an 824pt tile centred on a 1024pt canvas.
    let tile = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185 * unit, cornerHeight: 185 * unit, transform: nil)

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -10 * unit),
        blur: 24 * unit,
        color: NSColor.black.withAlphaComponent(0.28).cgColor
    )
    context.addPath(shape)
    context.setFillColor(NSColor(srgbRed: 0.85, green: 0.62, blue: 0.16, alpha: 1).cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let colors = [
        NSColor(srgbRed: 0.97, green: 0.76, blue: 0.27, alpha: 1).cgColor,
        NSColor(srgbRed: 0.80, green: 0.52, blue: 0.10, alpha: 1).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: tile.midX, y: tile.maxY),
        end: CGPoint(x: tile.midX, y: tile.minY),
        options: []
    )
    context.restoreGState()

    // The check, weighted to read at 16 pixels.
    let check = CGMutablePath()
    check.move(to: CGPoint(x: 322 * unit, y: 500 * unit))
    check.addLine(to: CGPoint(x: 456 * unit, y: 366 * unit))
    check.addLine(to: CGPoint(x: 712 * unit, y: 668 * unit))

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -6 * unit),
        blur: 14 * unit,
        color: NSColor(srgbRed: 0.45, green: 0.27, blue: 0.02, alpha: 0.45).cgColor
    )
    context.addPath(check)
    context.setStrokeColor(NSColor.white.cgColor)
    context.setLineWidth(92 * unit)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
    context.restoreGState()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    draw(size: CGFloat(pixels), in: context.cgContext)
    context.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let slots: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

var images: [[String: String]] = []
for slot in slots {
    let name = "icon_\(slot.points)x\(slot.points)\(slot.scale == 2 ? "@2x" : "").png"
    try png(pixels: slot.points * slot.scale).write(to: output.appendingPathComponent(name))
    images.append([
        "filename": name,
        "idiom": "mac",
        "scale": "\(slot.scale)x",
        "size": "\(slot.points)x\(slot.points)",
    ])
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))

let catalog: [String: Any] = ["info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.deletingLastPathComponent().appendingPathComponent("Contents.json"))

print("✓ wrote \(slots.count) sizes to \(output.path)")
