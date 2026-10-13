#!/usr/bin/env swift
// Turns the raw panel captures in Store/screenshots/raw/ into the framed,
// captioned images the Mac App Store listing uses.
//
//   swift Scripts/compose-screenshots.swift        (or: make screenshots)
//
// The App Store accepts Mac screenshots at a handful of exact sizes, and a menu
// bar panel is nowhere near any of them, so each capture is placed on a
// 2880x1800 canvas beside a line saying what it shows. The captures are real:
// they come from `make preview FIXTURE=… ` with `--bare`, which draws the panel
// against the sample data and nothing else. Only the frame around them is made
// here.
//
// The app's name is read from Store/metadata/en-US/name.txt, so the wordmark on
// every image follows the listing.

import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let rawDirectory = root.appendingPathComponent("Store/screenshots/raw")
let outDirectory = root.appendingPathComponent("Store/screenshots/mac")
let appName = ((try? String(contentsOf: root.appendingPathComponent("Store/metadata/en-US/name.txt"), encoding: .utf8)) ?? "GitCleared")
    .trimmingCharacters(in: .whitespacesAndNewlines)

struct Shot {
    let source: String
    let output: String
    let headline: String
    let detail: String
}

let shots = [
    Shot(source: "queue", output: "01-queue",
         headline: "Everything waiting on you.",
         detail: "Held deployments first, then the pull requests that are ready to land."),
    Shot(source: "all-clear", output: "02-all-clear",
         headline: "Quiet when the runway is clear.",
         detail: "No badge and no noise until something needs you."),
    Shot(source: "start-a-workflow", output: "03-start-a-workflow",
         headline: "Start a workflow by hand.",
         detail: "Only the ones that can be, with the inputs each one declares."),
    Shot(source: "settings", output: "04-settings",
         headline: "Tuned to how you work.",
         detail: "Launch at login, notifications, merge method, and which repositories to watch."),
    Shot(source: "connect", output: "05-connect",
         headline: "One token, kept in your Keychain.",
         detail: "It talks to GitHub as you, and to nothing else."),
]

let canvas = CGSize(width: 2880, height: 1800)
let amber = NSColor(srgbRed: 0.97, green: 0.76, blue: 0.27, alpha: 1)

func bitmap(_ image: NSImage) -> NSBitmapImageRep? {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    return NSBitmapImageRep(cgImage: cg)
}

/// The capture with any blank strip below the panel removed. A bare preview
/// window is a little taller than the panel it shows.
func trimmed(_ image: NSImage) -> CGImage? {
    guard let rep = bitmap(image), let cg = rep.cgImage else { return nil }
    // The window's rounded corners are in the capture too, so the edges of a
    // row are left out of the comparison.
    let inset = 80
    func isBlank(row: Int) -> Bool {
        guard let reference = rep.colorAt(x: inset, y: row) else { return false }
        for x in stride(from: inset, to: rep.pixelsWide - inset, by: 6) {
            guard let colour = rep.colorAt(x: x, y: row) else { return false }
            if abs(colour.redComponent - reference.redComponent) > 0.02
                || abs(colour.greenComponent - reference.greenComponent) > 0.02
                || abs(colour.blueComponent - reference.blueComponent) > 0.02 { return false }
        }
        return true
    }
    var last = rep.pixelsHigh - 1
    while last > 0, isBlank(row: last) { last -= 1 }
    let height = min(rep.pixelsHigh, last + 1 + 20)   // the footer's own bottom padding
    return cg.cropping(to: CGRect(x: 0, y: 0, width: rep.pixelsWide, height: height))
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, colour: NSColor, lineHeight: CGFloat = 1.08) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineHeightMultiple = lineHeight
    return NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: colour,
        .paragraphStyle: paragraph,
        .kern: size > 80 ? -1.5 : 0,
    ])
}

func height(of string: NSAttributedString, width: CGFloat) -> CGFloat {
    ceil(string.boundingRect(with: CGSize(width: width, height: 4000), options: [.usesLineFragmentOrigin]).height)
}

try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
let icon = NSImage(contentsOf: root.appendingPathComponent("docs/icon.png"))

for shot in shots {
    guard let raw = NSImage(contentsOf: rawDirectory.appendingPathComponent(shot.source + ".png")),
          let capture = trimmed(raw)
    else {
        print("✖ missing Store/screenshots/raw/\(shot.source).png")
        continue
    }

    // Drawn straight into a context with no alpha channel: the store rejects
    // screenshots that have one.
    guard let context = CGContext(
        data: nil, width: Int(canvas.width), height: Int(canvas.height),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError("could not create a drawing context") }
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high

    // Night sky behind the tower, with a little of the amber coming up from below.
    NSGradient(colors: [
        NSColor(srgbRed: 0.07, green: 0.09, blue: 0.13, alpha: 1),
        NSColor(srgbRed: 0.12, green: 0.15, blue: 0.21, alpha: 1),
    ])!.draw(in: CGRect(origin: .zero, size: canvas), angle: 90)
    NSGradient(colors: [amber.withAlphaComponent(0.16), amber.withAlphaComponent(0)])!
        .draw(in: CGRect(x: 0, y: 0, width: canvas.width, height: 620), angle: 90)

    // The panel, on the right.
    let region = CGRect(x: 1560, y: 150, width: 1120, height: 1500)
    let scale = min(region.width / CGFloat(capture.width), region.height / CGFloat(capture.height), 1.42)
    let size = CGSize(width: CGFloat(capture.width) * scale, height: CGFloat(capture.height) * scale)
    let frame = CGRect(x: region.midX - size.width / 2, y: region.midY - size.height / 2, width: size.width, height: size.height)
    let card = CGPath(roundedRect: frame, cornerWidth: 34, cornerHeight: 34, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -26), blur: 70, color: NSColor.black.withAlphaComponent(0.55).cgColor)
    context.addPath(card)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(card)
    context.clip()
    context.draw(capture, in: frame)
    context.restoreGState()

    // The words, on the left, centred as a block.
    let column: CGFloat = 1140
    let left: CGFloat = 220
    let headline = text(shot.headline, size: 112, weight: .bold, colour: .white, lineHeight: 1.02)
    let detail = text(shot.detail, size: 50, weight: .regular, colour: NSColor.white.withAlphaComponent(0.74), lineHeight: 1.22)
    let wordmark = text(appName, size: 54, weight: .semibold, colour: amber)
    let iconSide: CGFloat = 132
    let headlineHeight = height(of: headline, width: column)
    let detailHeight = height(of: detail, width: column)
    let block = iconSide + 86 + headlineHeight + 40 + detailHeight
    var y = (canvas.height + block) / 2

    y -= iconSide
    icon?.draw(in: CGRect(x: left - 14, y: y, width: iconSide, height: iconSide))
    let wordmarkHeight = height(of: wordmark, width: column)
    wordmark.draw(with: CGRect(x: left + iconSide + 14, y: y + (iconSide - wordmarkHeight) / 2, width: column, height: wordmarkHeight),
                  options: [.usesLineFragmentOrigin])
    y -= 86 + headlineHeight
    headline.draw(with: CGRect(x: left, y: y, width: column, height: headlineHeight), options: [.usesLineFragmentOrigin])
    y -= 40 + detailHeight
    detail.draw(with: CGRect(x: left, y: y, width: column, height: detailHeight), options: [.usesLineFragmentOrigin])

    graphics.flushGraphics()

    let url = outDirectory.appendingPathComponent(shot.output + ".png")
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("could not write \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("✓ \(url.lastPathComponent)")
}
