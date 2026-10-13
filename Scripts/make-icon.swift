#!/usr/bin/env swift
// Draws GitCleared's app icon and writes every size the asset catalog needs.
//
//   swift Scripts/make-icon.swift        (or: make icon)
//
// Also writes docs/icon.png, the copy shown at the top of the README.
//
// The icon is drawn in code so it can be regenerated and reviewed like the
// rest of the source: an amber tile — the colour of a held deployment — with
// an air traffic control tower on it. "Cleared" is the tower's word: nothing
// leaves the gate until it says so. The tower is drawn here rather than
// borrowed from SF Symbols, which has no such glyph and which Apple's licence
// does not allow in an app icon anyway.

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

    // The tower: a stem with a wide, flat head. Every part is at least a
    // pixel across at 16 pixels, so the silhouette survives the smallest size.
    let centre: CGFloat = 512

    /// A four-sided shape symmetric about the centre line, by its two widths.
    func band(from bottom: CGFloat, width bottomWidth: CGFloat, to top: CGFloat, width topWidth: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [
            CGPoint(x: (centre - bottomWidth / 2) * unit, y: bottom * unit),
            CGPoint(x: (centre + bottomWidth / 2) * unit, y: bottom * unit),
            CGPoint(x: (centre + topWidth / 2) * unit, y: top * unit),
            CGPoint(x: (centre - topWidth / 2) * unit, y: top * unit),
        ])
        path.closeSubpath()
        return path
    }

    func slab(from bottom: CGFloat, to top: CGFloat, width: CGFloat, radius: CGFloat) -> CGPath {
        CGPath(
            roundedRect: CGRect(x: (centre - width / 2) * unit, y: bottom * unit, width: width * unit, height: (top - bottom) * unit),
            cornerWidth: radius * unit,
            cornerHeight: radius * unit,
            transform: nil
        )
    }

    // One path, filled once, so the parts cast a single shadow between them.
    let tower = CGMutablePath()
    tower.addPath(slab(from: 214, to: 268, width: 300, radius: 16))            // plinth
    tower.addPath(band(from: 262, width: 168, to: 548, width: 128))            // shaft
    tower.addPath(band(from: 534, width: 132, to: 566, width: 330))            // collar under the cab
    tower.addPath(band(from: 560, width: 330, to: 706, width: 420))            // cab, leaning outward
    tower.addPath(slab(from: 700, to: 748, width: 456, radius: 14))            // roof
    tower.addPath(slab(from: 742, to: 800, width: 64, radius: 8))              // mast
    tower.addEllipse(in: CGRect(x: (centre - 34) * unit, y: 782 * unit, width: 68 * unit, height: 68 * unit)) // beacon

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -6 * unit),
        blur: 14 * unit,
        color: NSColor(srgbRed: 0.45, green: 0.27, blue: 0.02, alpha: 0.45).cgColor
    )
    context.addPath(tower)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()

    // The cab's glass: a band of the tile's own amber showing through, which
    // follows the slant of the cab walls. Left out at 16 pixels, where it is
    // about a pixel tall and only greys the cab; a solid head reads better.
    func cabWidth(at y: CGFloat) -> CGFloat { 330 + (420 - 330) * (y - 560) / (706 - 560) }
    let sill: CGFloat = 598
    let lintel: CGFloat = 668
    let inset: CGFloat = 56
    if size >= 32 {
        context.addPath(band(from: sill, width: cabWidth(at: sill) - inset, to: lintel, width: cabWidth(at: lintel) - inset))
        context.setFillColor(NSColor(srgbRed: 0.72, green: 0.45, blue: 0.07, alpha: 1).cgColor)
        context.fillPath()
    }

    // Mullions, only where there are pixels to draw them with.
    if size >= 128 {
        context.setFillColor(NSColor.white.cgColor)
        for offset in [-96, 0, 96] as [CGFloat] {
            // Lean each one with the wall it is nearest, like the real thing.
            let lean = offset / 330 * (420 - 330) / 2 * (lintel - sill) / (706 - 560)
            let mullion = CGMutablePath()
            mullion.addLines(between: [
                CGPoint(x: (centre + offset - 8) * unit, y: sill * unit),
                CGPoint(x: (centre + offset + 8) * unit, y: sill * unit),
                CGPoint(x: (centre + offset + lean + 8) * unit, y: lintel * unit),
                CGPoint(x: (centre + offset + lean - 8) * unit, y: lintel * unit),
            ])
            mullion.closeSubpath()
            context.addPath(mullion)
        }
        context.fillPath()
    }
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

// A copy the README can show. GitHub cannot render an image out of an asset
// catalog, and a README without the icon does not look like the app.
let readmeIcon = URL(fileURLWithPath: "docs/icon.png")
try FileManager.default.createDirectory(at: readmeIcon.deletingLastPathComponent(), withIntermediateDirectories: true)
try png(pixels: 512).write(to: readmeIcon)

print("✓ wrote \(slots.count) sizes to \(output.path), and \(readmeIcon.path)")
