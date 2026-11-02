import AppKit
import CoreGraphics
import Foundation
import ImageIO

func createIcon(size: Int) -> CGImage? {
    let width = size
    let height = size
    let scale = Double(size) / 1024.0

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

    // Helper functions for 1024x1024 base coordinate space
    func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
        CGColor(colorSpace: colorSpace, components: [r / 255.0, g / 255.0, b / 255.0, a])!
    }

    // 1. Draw macOS squircle with drop shadow
    let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let cornerRadius: CGFloat = 824.0 * 0.224 // ~184.58px

    ctx.saveGState()
    // Soft drop shadow
    ctx.setShadow(
        offset: CGSize(width: 0, height: -24),
        blur: 38,
        color: rgb(0, 0, 0, 0.40)
    )

    let squirclePath = CGPath(
        roundedRect: iconRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )

    // Base background fill for shadow
    ctx.addPath(squirclePath)
    ctx.setFillColor(rgb(15, 23, 42, 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // 2. Clip inside squircle for luxurious oceanic blue gradient
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // Deep oceanic to vibrant cyan gradient (#0F172A -> #1E3A8A -> #0284C7 -> #38BDF8)
    let gradientColors = [
        rgb(15, 23, 42, 1.0),   // #0F172A (Deep Slate/Ocean Navy)
        rgb(30, 58, 138, 1.0),  // #1E3A8A (Deep Royal Blue)
        rgb(2, 132, 199, 1.0),  // #0284C7 (Vibrant Oceanic Blue)
        rgb(56, 189, 248, 1.0)  // #38BDF8 (Vibrant Cyan/Sky)
    ] as CFArray
    let gradientLocations: [CGFloat] = [0.0, 0.35, 0.72, 1.0]
    guard let bgGradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: gradientLocations) else {
        return nil
    }

    // Draw diagonal gradient from top-left to bottom-right
    ctx.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: 250, y: 924),
        end: CGPoint(x: 774, y: 100),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Top lighting sheen / ambient radial glow
    if let sheenGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [rgb(255, 255, 255, 0.28), rgb(56, 189, 248, 0.0)] as CFArray,
        locations: [0.0, 1.0]
    ) {
        ctx.drawRadialGradient(
            sheenGradient,
            startCenter: CGPoint(x: 512, y: 900),
            startRadius: 0,
            endCenter: CGPoint(x: 512, y: 700),
            endRadius: 500,
            options: []
        )
    }

    // Bottom deep vignette
    if let vignette = CGGradient(
        colorsSpace: colorSpace,
        colors: [rgb(10, 15, 30, 0.0), rgb(10, 15, 30, 0.45)] as CFArray,
        locations: [0.0, 1.0]
    ) {
        ctx.drawRadialGradient(
            vignette,
            startCenter: CGPoint(x: 512, y: 512),
            startRadius: 280,
            endCenter: CGPoint(x: 512, y: 512),
            endRadius: 560,
            options: []
        )
    }

    // Subtle background mesh/concentric speed rings (representing high-throughput network stream)
    ctx.saveGState()
    ctx.setLineWidth(1.5)
    for r in stride(from: 140, through: 380, by: 70) {
        ctx.addArc(center: CGPoint(x: 512, y: 470), radius: CGFloat(r), startAngle: 0, endAngle: .pi * 2, clockwise: true)
        ctx.setStrokeColor(rgb(255, 255, 255, 0.04))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // 3. Center Artwork:
    // High-tech aerodynamic download arrow formed by 4 parallel glowing acceleration stream bars
    // symbolizing multi-chunk acceleration and ultra-fast throughput, with a subtle glowing circular or tray base.

    // A. Glowing Base Tray / Dish
    // Tray sits at y ~ 260
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: 24, color: rgb(56, 189, 248, 0.75))

    let trayPath = CGMutablePath()
    // A modern curved tray with rounded ends
    let trayY: CGFloat = 255
    let trayWidth: CGFloat = 380
    let trayHeight: CGFloat = 42
    let trayLeft: CGFloat = 512 - trayWidth / 2
    let trayRect = CGRect(x: trayLeft, y: trayY, width: trayWidth, height: trayHeight)
    trayPath.addRoundedRect(in: trayRect, cornerWidth: 21, cornerHeight: 21)

    ctx.addPath(trayPath)
    if let trayGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [rgb(2, 132, 199, 0.85), rgb(56, 189, 248, 0.95), rgb(224, 242, 254, 1.0)] as CFArray,
        locations: [0.0, 0.5, 1.0]
    ) {
        ctx.saveGState()
        ctx.addPath(trayPath)
        ctx.clip()
        ctx.drawLinearGradient(
            trayGradient,
            start: CGPoint(x: 512, y: trayY),
            end: CGPoint(x: 512, y: trayY + trayHeight),
            options: []
        )
        ctx.restoreGState()
    }

    // Inner tray rim highlight
    let innerTrayRect = CGRect(x: trayLeft + 4, y: trayY + 4, width: trayWidth - 8, height: trayHeight - 8)
    ctx.addPath(CGPath(roundedRect: innerTrayRect, cornerWidth: 17, cornerHeight: 17, transform: nil))
    ctx.setStrokeColor(rgb(255, 255, 255, 0.45))
    ctx.setLineWidth(1.5)
    ctx.strokePath()
    ctx.restoreGState()

    // B. Acceleration Stream Bars + Arrow Head
    // We create 4 parallel vertical glowing stream bars representing 4 concurrent chunks.
    // Width = 42px each, spacing = 22px. Total width = 4 * 42 + 3 * 22 = 234px.
    // Center at 512. Left = 512 - 117 = 395.
    // Bar centers:
    // Bar 0: x = 395 + 21 = 416
    // Bar 1: x = 416 + 64 = 480
    // Bar 2: x = 480 + 64 = 544
    // Bar 3: x = 544 + 64 = 608

    let barWidth: CGFloat = 40
    let barSpacing: CGFloat = 20
    let totalBarsWidth = (4 * barWidth) + (3 * barSpacing)
    let startX = 512 - totalBarsWidth / 2

    // Stream bars start at y = 780 and flow downwards towards arrowhead at y ~ 450
    // Outer bars (0 and 3) are shorter at top to create an aerodynamic stepped contour:
    // Bar 0: top 720, bottom 490
    // Bar 1: top 790, bottom 450
    // Bar 2: top 790, bottom 450
    // Bar 3: top 720, bottom 490

    let barConfigs: [(top: CGFloat, bottom: CGFloat, alphaMultiplier: CGFloat)] = [
        (730, 500, 0.85),
        (800, 470, 1.0),
        (800, 470, 1.0),
        (730, 500, 0.85)
    ]

    for (index, config) in barConfigs.enumerated() {
        let x = startX + CGFloat(index) * (barWidth + barSpacing)
        let rect = CGRect(x: x, y: config.bottom, width: barWidth, height: config.top - config.bottom)

        ctx.saveGState()
        // Cyan neon glow behind stream bars
        ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: 20, color: rgb(56, 189, 248, 0.7 * config.alphaMultiplier))

        let barPath = CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
        ctx.addPath(barPath)
        ctx.clip()

        // Gradient from faded cyan at top to brilliant white at bottom (flow acceleration)
        if let barGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                rgb(14, 165, 233, 0.40 * config.alphaMultiplier),
                rgb(56, 189, 248, 0.85 * config.alphaMultiplier),
                rgb(255, 255, 255, 1.0)
            ] as CFArray,
            locations: [0.0, 0.65, 1.0]
        ) {
            ctx.drawLinearGradient(
                barGrad,
                start: CGPoint(x: x, y: config.top),
                end: CGPoint(x: x, y: config.bottom),
                options: []
            )
        }

        // Inner specular reflection line
        let highlightLine = CGRect(x: x + barWidth / 2 - 2, y: config.bottom + 10, width: 4, height: config.top - config.bottom - 20)
        ctx.addPath(CGPath(roundedRect: highlightLine, cornerWidth: 2, cornerHeight: 2, transform: nil))
        ctx.setFillColor(rgb(255, 255, 255, 0.55))
        ctx.fillPath()

        ctx.restoreGState()
    }

    // C. The Aerodynamic Chevron Arrowhead
    // Pointing downwards at y = 340 (just above the tray at 255).
    // Apex at (512, 335).
    // Left tip at (315, 505).
    // Right tip at (709, 505).
    // Notch at (512, 425).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 28, color: rgb(56, 189, 248, 0.85))

    let arrowPath = CGMutablePath()
    let apex = CGPoint(x: 512, y: 330)
    let leftWing = CGPoint(x: 320, y: 495)
    let rightWing = CGPoint(x: 704, y: 495)
    let notch = CGPoint(x: 512, y: 420)

    // Build smooth aerodynamic chevron
    arrowPath.move(to: apex)
    arrowPath.addLine(to: leftWing)
    arrowPath.addLine(to: CGPoint(x: 350, y: 515)) // wing thickness
    arrowPath.addLine(to: notch)
    arrowPath.addLine(to: CGPoint(x: 674, y: 515))
    arrowPath.addLine(to: rightWing)
    arrowPath.closeSubpath()

    ctx.addPath(arrowPath)
    ctx.clip()

    // Blazing white-cyan gradient on arrowhead
    if let arrowGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            rgb(255, 255, 255, 1.0),
            rgb(224, 242, 254, 1.0),
            rgb(56, 189, 248, 1.0),
            rgb(2, 132, 199, 1.0)
        ] as CFArray,
        locations: [0.0, 0.35, 0.75, 1.0]
    ) {
        ctx.drawLinearGradient(
            arrowGrad,
            start: CGPoint(x: 512, y: 330),
            end: CGPoint(x: 512, y: 515),
            options: []
        )
    }
    ctx.restoreGState()

    // Arrowhead border stroke for crisp vector precision
    ctx.saveGState()
    ctx.addPath(arrowPath)
    ctx.setLineWidth(2.0)
    ctx.setStrokeColor(rgb(255, 255, 255, 0.65))
    ctx.strokePath()
    ctx.restoreGState()

    // D. Multi-chunk data glow pulses (representing packets racing down into the arrowhead)
    for (idx, pulseY) in [450, 410, 370].enumerated() {
        let pulseRadius: CGFloat = idx == 0 ? 9 : (idx == 1 ? 7 : 5)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 16, color: rgb(255, 255, 255, 0.9))
        ctx.addArc(center: CGPoint(x: 512, y: CGFloat(pulseY)), radius: pulseRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        ctx.setFillColor(rgb(255, 255, 255, 0.95))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // 4. Inner Border Highlight along squircle edges (macOS HIG signature top-light effect)
    ctx.restoreGState() // restores clip of squircle

    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setLineWidth(2.5)
    ctx.setStrokeColor(rgb(255, 255, 255, 0.35))
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()
}

func savePNG(image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "IconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "IconGen", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to write PNG image"])
    }
}

// Generate iconset
let iconsetDir = URL(fileURLWithPath: "HyperFetch.iconset")
let fm = FileManager.default
try? fm.removeItem(at: iconsetDir)
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let sizes: [(name: String, size: Int)] = [
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

print("Rendering HyperFetch icons...")
for (name, size) in sizes {
    guard let img = createIcon(size: size) else {
        fatalError("Failed to render icon at size \(size)")
    }
    let fileURL = iconsetDir.appendingPathComponent(name)
    try savePNG(image: img, to: fileURL)
    print("  ✓ Rendered \(name) (\(size)x\(size))")
}

print("Iconset created successfully at \(iconsetDir.path)")

// Output to Sources/HyperFetchApp/Resources/AppIcon.icns
let resourcesDir = URL(fileURLWithPath: "Sources/HyperFetchApp/Resources")
try? fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
let icnsOutputURL = resourcesDir.appendingPathComponent("AppIcon.icns")

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsOutputURL.path]
do {
    try iconutil.run()
    iconutil.waitUntilExit()
    if iconutil.terminationStatus == 0 {
        print("✓ Generated \(icnsOutputURL.path)")
        try? fm.removeItem(at: iconsetDir)
    } else {
        print("✗ iconutil failed with exit code \(iconutil.terminationStatus)")
    }
} catch {
    print("✗ Failed to run iconutil: \(error)")
}
