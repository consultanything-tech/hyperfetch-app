#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

func renderDMGBackground(scale: CGFloat, version: String = "1.0.0") -> CGImage {
    let pointWidth: CGFloat = 660
    let pointHeight: CGFloat = 420
    let pixelWidth = Int(pointWidth * scale)
    let pixelHeight = Int(pointHeight * scale)

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil,
        width: pixelWidth,
        height: pixelHeight,
        bitsPerComponent: 8,
        bytesPerRow: pixelWidth * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Failed to create CoreGraphics bitmap context")
    }

    // Flip context so (0,0) is top-left in points (matching macOS Finder window coordinates)
    ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
    ctx.scaleBy(x: scale, y: -scale)

    let nsContext = NSGraphicsContext(cgContext: ctx, flipped: true)
    let prevContext = NSGraphicsContext.current
    NSGraphicsContext.current = nsContext
    defer { NSGraphicsContext.current = prevContext }

    func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
        CGColor(colorSpace: colorSpace, components: [r / 255.0, g / 255.0, b / 255.0, a])!
    }

    func nsColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> NSColor {
        NSColor(red: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
    }

    // -------------------------------------------------------------
    // 1. Background: Luxurious dark theme (#0D1117 to #161B22)
    // -------------------------------------------------------------
    let bgColors = [
        rgb(13, 17, 23, 1.0),   // #0D1117 - deep slate/navy
        rgb(16, 21, 28, 1.0),
        rgb(22, 27, 34, 1.0)    // #161B22 - deep charcoal/slate
    ] as CFArray
    let bgLocations: [CGFloat] = [0.0, 0.45, 1.0]

    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: 80, y: 0),
            end: CGPoint(x: 580, y: pointHeight),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    // Soft top ambient radial glow (cyan sheen over header)
    if let topGlow = CGGradient(
        colorsSpace: colorSpace,
        colors: [rgb(56, 189, 248, 0.08), rgb(56, 189, 248, 0.0)] as CFArray,
        locations: [0.0, 1.0]
    ) {
        ctx.drawRadialGradient(
            topGlow,
            startCenter: CGPoint(x: 330, y: 40),
            startRadius: 0,
            endCenter: CGPoint(x: 330, y: 40),
            endRadius: 280,
            options: []
        )
    }

    // Ambient radial glow behind left slot (HyperFetch speed aura)
    if let leftSlotGlow = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            rgb(56, 189, 248, 0.18),
            rgb(37, 99, 235, 0.06),
            rgb(13, 17, 23, 0.0)
        ] as CFArray,
        locations: [0.0, 0.55, 1.0]
    ) {
        ctx.drawRadialGradient(
            leftSlotGlow,
            startCenter: CGPoint(x: 180, y: 210),
            startRadius: 0,
            endCenter: CGPoint(x: 180, y: 210),
            endRadius: 170,
            options: []
        )
    }

    // Ambient radial glow behind center arrow
    if let arrowGlow = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            rgb(59, 130, 246, 0.16),
            rgb(56, 189, 248, 0.03),
            rgb(13, 17, 23, 0.0)
        ] as CFArray,
        locations: [0.0, 0.6, 1.0]
    ) {
        ctx.drawRadialGradient(
            arrowGlow,
            startCenter: CGPoint(x: 330, y: 210),
            startRadius: 0,
            endCenter: CGPoint(x: 330, y: 210),
            endRadius: 130,
            options: []
        )
    }

    // Ambient radial glow behind Applications slot
    if let rightSlotGlow = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            rgb(99, 102, 241, 0.08),
            rgb(13, 17, 23, 0.0)
        ] as CFArray,
        locations: [0.0, 1.0]
    ) {
        ctx.drawRadialGradient(
            rightSlotGlow,
            startCenter: CGPoint(x: 480, y: 210),
            startRadius: 0,
            endCenter: CGPoint(x: 480, y: 210),
            endRadius: 150,
            options: []
        )
    }

    // Elegant window border inset
    let windowBorderRect = CGRect(x: 1, y: 1, width: pointWidth - 2, height: pointHeight - 2)
    let windowBorderPath = CGPath(roundedRect: windowBorderRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
    ctx.setStrokeColor(rgb(255, 255, 255, 0.06))
    ctx.setLineWidth(1.0)
    ctx.addPath(windowBorderPath)
    ctx.strokePath()

    // -------------------------------------------------------------
    // 2. Center Icon Drop Guides: Left slot (180, 210) & Right slot (480, 210)
    // -------------------------------------------------------------
    func drawGuideSlot(center: CGPoint, size: CGFloat, cornerRadius: CGFloat, isAccent: Bool) {
        let rect = CGRect(
            x: center.x - size / 2.0,
            y: center.y - size / 2.0,
            width: size,
            height: size
        )
        let squirclePath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // Glassmorphic translucent surface fill
        ctx.saveGState()
        let fillColors = isAccent ? [
            rgb(56, 189, 248, 0.06),
            rgb(255, 255, 255, 0.015)
        ] as CFArray : [
            rgb(255, 255, 255, 0.035),
            rgb(255, 255, 255, 0.008)
        ] as CFArray

        if let fillGradient = CGGradient(colorsSpace: colorSpace, colors: fillColors, locations: [0.0, 1.0]) {
            ctx.addPath(squirclePath)
            ctx.clip()
            ctx.drawLinearGradient(
                fillGradient,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.maxY),
                options: []
            )
        }
        ctx.restoreGState()

        // Outer glow & border stroke
        ctx.saveGState()
        if isAccent {
            ctx.setShadow(
                offset: .zero,
                blur: 16,
                color: rgb(56, 189, 248, 0.35)
            )
            ctx.setStrokeColor(rgb(56, 189, 248, 0.50))
        } else {
            ctx.setShadow(
                offset: CGSize(width: 0, height: 2),
                blur: 12,
                color: rgb(0, 0, 0, 0.35)
            )
            ctx.setStrokeColor(rgb(255, 255, 255, 0.16))
        }
        ctx.setLineWidth(1.5)
        ctx.addPath(squirclePath)
        ctx.strokePath()
        ctx.restoreGState()

        // High-precision alignment target brackets
        let bracketLen: CGFloat = 8
        let inset: CGFloat = 13
        ctx.saveGState()
        ctx.setStrokeColor(isAccent ? rgb(56, 189, 248, 0.40) : rgb(255, 255, 255, 0.15))
        ctx.setLineWidth(1.0)
        // Top-left
        ctx.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset + bracketLen))
        ctx.addLine(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
        ctx.addLine(to: CGPoint(x: rect.minX + inset + bracketLen, y: rect.minY + inset))
        // Top-right
        ctx.move(to: CGPoint(x: rect.maxX - inset - bracketLen, y: rect.minY + inset))
        ctx.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        ctx.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset + bracketLen))
        // Bottom-left
        ctx.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset - bracketLen))
        ctx.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        ctx.addLine(to: CGPoint(x: rect.minX + inset + bracketLen, y: rect.maxY - inset))
        // Bottom-right
        ctx.move(to: CGPoint(x: rect.maxX - inset - bracketLen, y: rect.maxY - inset))
        ctx.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        ctx.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset - bracketLen))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // Left Slot (center at (180, 210)) - for HyperFetch.app
    drawGuideSlot(center: CGPoint(x: 180, y: 210), size: 154, cornerRadius: 34, isAccent: true)

    // Right Slot (center at (480, 210)) - for Applications
    drawGuideSlot(center: CGPoint(x: 480, y: 210), size: 154, cornerRadius: 34, isAccent: false)

    // -------------------------------------------------------------
    // 3. Middle Arrow: between x=265 and x=395 at y=210
    // Multi-chunk speed streaks & glowing gradient arrow
    // -------------------------------------------------------------
    struct Streak {
        let x1: CGFloat
        let x2: CGFloat
        let y: CGFloat
        let alpha: CGFloat
        let width: CGFloat
    }

    let streaks: [Streak] = [
        Streak(x1: 265, x2: 290, y: 196, alpha: 0.40, width: 2.0),
        Streak(x1: 298, x2: 335, y: 196, alpha: 0.70, width: 2.0),
        Streak(x1: 260, x2: 280, y: 202, alpha: 0.50, width: 2.5),
        Streak(x1: 288, x2: 350, y: 202, alpha: 0.85, width: 2.5),
        Streak(x1: 262, x2: 284, y: 218, alpha: 0.50, width: 2.5),
        Streak(x1: 292, x2: 352, y: 218, alpha: 0.85, width: 2.5),
        Streak(x1: 268, x2: 295, y: 224, alpha: 0.40, width: 2.0),
        Streak(x1: 304, x2: 338, y: 224, alpha: 0.70, width: 2.0)
    ]

    for s in streaks {
        ctx.saveGState()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: s.x1, y: s.y))
        path.addLine(to: CGPoint(x: s.x2, y: s.y))
        ctx.setLineCap(.round)
        ctx.setLineWidth(s.width)
        ctx.setStrokeColor(rgb(56, 189, 248, s.alpha))
        ctx.setShadow(offset: .zero, blur: 6, color: rgb(56, 189, 248, s.alpha * 0.7))
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // Speed chunk particles/nodes
    let particles: [(x: CGFloat, y: CGFloat, r: CGFloat, a: CGFloat)] = [
        (294, 196, 2.0, 0.90),
        (339, 196, 2.2, 0.80),
        (284, 202, 2.5, 0.90),
        (356, 202, 2.5, 0.95),
        (288, 218, 2.5, 0.90),
        (358, 218, 2.5, 0.95),
        (300, 224, 2.0, 0.85),
        (342, 224, 2.2, 0.75)
    ]
    for p in particles {
        ctx.saveGState()
        ctx.setFillColor(rgb(125, 211, 252, p.a))
        ctx.setShadow(offset: .zero, blur: 6, color: rgb(56, 189, 248, p.a))
        ctx.fillEllipse(in: CGRect(x: p.x - p.r, y: p.y - p.r, width: p.r * 2, height: p.r * 2))
        ctx.restoreGState()
    }

    // Main sleek arrow shaft & chevron head
    let shaftRect = CGRect(x: 275, y: 207.0, width: 95, height: 6.0)
    let shaftPath = CGPath(roundedRect: shaftRect, cornerWidth: 3.0, cornerHeight: 3.0, transform: nil)

    let headPath = CGMutablePath()
    headPath.move(to: CGPoint(x: 395, y: 210))          // Arrowhead tip
    headPath.addLine(to: CGPoint(x: 374, y: 195))      // Top wing
    headPath.addLine(to: CGPoint(x: 379, y: 207))      // Inner top notch
    headPath.addLine(to: CGPoint(x: 370, y: 207))      // Shaft seam
    headPath.addLine(to: CGPoint(x: 370, y: 213))      // Shaft seam
    headPath.addLine(to: CGPoint(x: 379, y: 213))      // Inner bottom notch
    headPath.addLine(to: CGPoint(x: 374, y: 225))      // Bottom wing
    headPath.closeSubpath()

    let arrowColors = [
        rgb(56, 189, 248, 1.0),   // Vibrant Cyan (#38BDF8)
        rgb(59, 130, 246, 1.0),   // Electric Blue (#3B82F6)
        rgb(37, 99, 235, 1.0)     // Royal Blue (#2563EB)
    ] as CFArray

    if let arrowGradient = CGGradient(colorsSpace: colorSpace, colors: arrowColors, locations: [0.0, 0.55, 1.0]) {
        // Outer arrow glow
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 14, color: rgb(56, 189, 248, 0.65))
        ctx.setFillColor(rgb(56, 189, 248, 0.9))
        ctx.addPath(shaftPath)
        ctx.addPath(headPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Gradient arrow fill
        ctx.saveGState()
        ctx.addPath(shaftPath)
        ctx.addPath(headPath)
        ctx.clip()
        ctx.drawLinearGradient(
            arrowGradient,
            start: CGPoint(x: 275, y: 210),
            end: CGPoint(x: 395, y: 210),
            options: []
        )
        ctx.restoreGState()
    }

    // -------------------------------------------------------------
    // 4. Top Branding: Title and Installation Instructions
    // -------------------------------------------------------------
    // "HyperFetch" Title
    let titleStr = "HyperFetch" as NSString
    let titleShadow = NSShadow()
    titleShadow.shadowColor = nsColor(0, 0, 0, 0.55)
    titleShadow.shadowOffset = NSSize(width: 0, height: -2)
    titleShadow.shadowBlurRadius = 8

    let titleFont = NSFont.systemFont(ofSize: 32, weight: .bold)
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: nsColor(248, 250, 252, 1.0), // #F8FAFC
        .shadow: titleShadow
    ]
    let titleSize = titleStr.size(withAttributes: titleAttrs)
    let titlePoint = CGPoint(x: (pointWidth - titleSize.width) / 2.0, y: 46)
    titleStr.draw(at: titlePoint, withAttributes: titleAttrs)

    // Subtitle / Instruction Caption
    let capStr = "Drag HyperFetch to Applications to install" as NSString
    let capFont = NSFont.systemFont(ofSize: 14, weight: .medium)
    let capAttrs: [NSAttributedString.Key: Any] = [
        .font: capFont,
        .foregroundColor: nsColor(148, 163, 184, 0.95) // #94A3B8
    ]
    let capSize = capStr.size(withAttributes: capAttrs)
    let capPoint = CGPoint(x: (pointWidth - capSize.width) / 2.0, y: 88)
    capStr.draw(at: capPoint, withAttributes: capAttrs)

    // -------------------------------------------------------------
    // 5. Bottom Footnote
    // -------------------------------------------------------------
    let vStr = version.hasPrefix("v") ? version : "v\(version)"
    let footStr = "\(vStr) • High-Speed Multi-Chunk Acceleration • Apple Silicon & Intel • macOS 14+" as NSString
    let footFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    let footAttrs: [NSAttributedString.Key: Any] = [
        .font: footFont,
        .foregroundColor: nsColor(100, 116, 139, 0.85) // #64748B
    ]
    let footSize = footStr.size(withAttributes: footAttrs)
    let footPoint = CGPoint(x: (pointWidth - footSize.width) / 2.0, y: 382)
    footStr.draw(at: footPoint, withAttributes: footAttrs)

    // -------------------------------------------------------------
    // Output CGImage
    // -------------------------------------------------------------
    guard let cgImage = ctx.makeImage() else {
        fatalError("Failed to create CGImage from context")
    }
    return cgImage
}

func generateAllDMGBackgroundAssets(targetPathOrDir: String, version: String = "1.0.0") {
    let pointWidth: CGFloat = 660
    let pointHeight: CGFloat = 420

    var dirURL: URL
    var isDir: ObjCBool = false
    let fm = FileManager.default
    if fm.fileExists(atPath: targetPathOrDir, isDirectory: &isDir), isDir.boolValue {
        dirURL = URL(fileURLWithPath: targetPathOrDir)
    } else if targetPathOrDir.hasSuffix(".png") || targetPathOrDir.hasSuffix(".tiff") {
        dirURL = URL(fileURLWithPath: targetPathOrDir).deletingLastPathComponent()
    } else {
        dirURL = URL(fileURLWithPath: targetPathOrDir)
    }

    try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)

    let image1x = renderDMGBackground(scale: 1.0, version: version)
    let image2x = renderDMGBackground(scale: 2.0, version: version)

    let rep1x = NSBitmapImageRep(cgImage: image1x)
    rep1x.size = NSSize(width: pointWidth, height: pointHeight)

    let rep2x = NSBitmapImageRep(cgImage: image2x)
    rep2x.size = NSSize(width: pointWidth, height: pointHeight)

    guard let pngData1x = rep1x.representation(using: .png, properties: [:]),
          let pngData2x = rep2x.representation(using: .png, properties: [:]),
          let tiffData1x = rep1x.representation(using: .tiff, properties: [:]),
          let tiffData2x = rep2x.representation(using: .tiff, properties: [:]) else {
        fatalError("Failed to encode PNG or TIFF data representations")
    }

    let pngURL1x = dirURL.appendingPathComponent("dmg_background.png")
    let pngURL2x = dirURL.appendingPathComponent("dmg_background@2x.png")
    let tiffURL1x = dirURL.appendingPathComponent("dmg_1x.tiff")
    let tiffURL2x = dirURL.appendingPathComponent("dmg_2x.tiff")
    let tiffURLCombined = dirURL.appendingPathComponent("dmg_background.tiff")

    do {
        try pngData1x.write(to: pngURL1x)
        try pngData2x.write(to: pngURL2x)
        try tiffData1x.write(to: tiffURL1x)
        try tiffData2x.write(to: tiffURL2x)
        print("Generated 1x PNG at \(pngURL1x.path) (660x420 px)")
        print("Generated 2x PNG at \(pngURL2x.path) (1320x840 px)")
        print("Generated 1x TIFF at \(tiffURL1x.path)")
        print("Generated 2x TIFF at \(tiffURL2x.path)")
    } catch {
        fatalError("Failed to write image files: \(error)")
    }

    // Combine 1x and 2x into a true macOS HiDPI multi-resolution TIFF
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
    proc.arguments = [
        "-cathidpicheck",
        tiffURL1x.path,
        tiffURL2x.path,
        "-out",
        tiffURLCombined.path
    ]
    do {
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            fatalError("tiffutil failed with exit code \(proc.terminationStatus)")
        }
        print("Generated HiDPI multi-resolution TIFF at \(tiffURLCombined.path)")
    } catch {
        fatalError("Failed to execute tiffutil: \(error)")
    }
}

let outArg = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/dmg_background.png"
let versionArg = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "1.0.0"
generateAllDMGBackgroundAssets(targetPathOrDir: outArg, version: versionArg)
