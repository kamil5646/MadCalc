import AppKit

struct IconSpec {
    let idiom: String
    let size: String
    let scale: String
    let pixelSize: Int
    let filename: String
}

let outputDirectory = URL(fileURLWithPath: "/Users/kamilkasprzak/Documents/inne/MadCalc_iOS/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let specs: [IconSpec] = [
    .init(idiom: "iphone", size: "20x20", scale: "2x", pixelSize: 40, filename: "AppIcon-20@2x.png"),
    .init(idiom: "iphone", size: "20x20", scale: "3x", pixelSize: 60, filename: "AppIcon-20@3x.png"),
    .init(idiom: "iphone", size: "29x29", scale: "2x", pixelSize: 58, filename: "AppIcon-29@2x.png"),
    .init(idiom: "iphone", size: "29x29", scale: "3x", pixelSize: 87, filename: "AppIcon-29@3x.png"),
    .init(idiom: "iphone", size: "40x40", scale: "2x", pixelSize: 80, filename: "AppIcon-40@2x.png"),
    .init(idiom: "iphone", size: "40x40", scale: "3x", pixelSize: 120, filename: "AppIcon-40@3x.png"),
    .init(idiom: "iphone", size: "60x60", scale: "2x", pixelSize: 120, filename: "AppIcon-60@2x.png"),
    .init(idiom: "iphone", size: "60x60", scale: "3x", pixelSize: 180, filename: "AppIcon-60@3x.png"),
    .init(idiom: "ipad", size: "20x20", scale: "1x", pixelSize: 20, filename: "AppIcon-20@1x.png"),
    .init(idiom: "ipad", size: "20x20", scale: "2x", pixelSize: 40, filename: "AppIcon-20@2x~ipad.png"),
    .init(idiom: "ipad", size: "29x29", scale: "1x", pixelSize: 29, filename: "AppIcon-29@1x.png"),
    .init(idiom: "ipad", size: "29x29", scale: "2x", pixelSize: 58, filename: "AppIcon-29@2x~ipad.png"),
    .init(idiom: "ipad", size: "40x40", scale: "1x", pixelSize: 40, filename: "AppIcon-40@1x.png"),
    .init(idiom: "ipad", size: "40x40", scale: "2x", pixelSize: 80, filename: "AppIcon-40@2x~ipad.png"),
    .init(idiom: "ipad", size: "76x76", scale: "1x", pixelSize: 76, filename: "AppIcon-76@1x.png"),
    .init(idiom: "ipad", size: "76x76", scale: "2x", pixelSize: 152, filename: "AppIcon-76@2x.png"),
    .init(idiom: "ipad", size: "83.5x83.5", scale: "2x", pixelSize: 167, filename: "AppIcon-83.5@2x.png"),
    .init(idiom: "ios-marketing", size: "1024x1024", scale: "1x", pixelSize: 1024, filename: "AppIcon-1024.png")
]

func renderIcon(pixelSize: Int) -> Data {
    let size = CGFloat(pixelSize)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Nie udało się stworzyć bitmapy dla ikony.")
    }

    bitmap.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Nie udało się utworzyć kontekstu dla ikony.")
    }
    NSGraphicsContext.current = graphicsContext

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor(calibratedRed: 0.06, green: 0.22, blue: 0.48, alpha: 1).setFill()
    NSBezierPath(rect: canvas).fill()

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.06, green: 0.22, blue: 0.48, alpha: 1),
        NSColor(srgbRed: 0.13, green: 0.39, blue: 0.74, alpha: 1),
        NSColor(srgbRed: 0.29, green: 0.59, blue: 0.93, alpha: 1)
    ])!
    gradient.draw(in: NSBezierPath(rect: canvas), angle: 42)

    NSColor.white.withAlphaComponent(0.08).setFill()
    NSBezierPath(ovalIn: NSRect(x: size * 0.12, y: size * 0.56, width: size * 0.76, height: size * 0.28)).fill()

    let railRect = NSRect(x: size * 0.17, y: size * 0.2, width: size * 0.66, height: size * 0.15)
    let railPath = NSBezierPath(roundedRect: railRect, xRadius: size * 0.045, yRadius: size * 0.045)
    NSColor.white.withAlphaComponent(0.96).setFill()
    railPath.fill()

    NSColor(srgbRed: 0.09, green: 0.31, blue: 0.59, alpha: 1).setStroke()
    for tick in 0...11 {
        let x = railRect.minX + CGFloat(tick) * (railRect.width / 11)
        let tickHeight = tick.isMultiple(of: 2) ? railRect.height * 0.48 : railRect.height * 0.32
        let tickPath = NSBezierPath()
        tickPath.lineWidth = size * 0.008
        tickPath.move(to: NSPoint(x: x, y: railRect.midY - tickHeight * 0.5))
        tickPath.line(to: NSPoint(x: x, y: railRect.midY + tickHeight * 0.5))
        tickPath.stroke()
    }

    let cutColor = NSColor(srgbRed: 0.99, green: 0.82, blue: 0.25, alpha: 1)
    for offset in [0.32, 0.62] {
        let cutRect = NSRect(x: railRect.minX + railRect.width * offset, y: railRect.minY + railRect.height * 0.08, width: size * 0.025, height: railRect.height * 0.84)
        let cutPath = NSBezierPath(roundedRect: cutRect, xRadius: size * 0.012, yRadius: size * 0.012)
        cutColor.setFill()
        cutPath.fill()
    }

    let shadow = NSShadow()
    shadow.shadowBlurRadius = size * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)

    let centeredParagraph = NSMutableParagraphStyle()
    centeredParagraph.alignment = .center

    let symbolAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size * 0.42, weight: .black),
        .foregroundColor: NSColor.white,
        .paragraphStyle: centeredParagraph,
        .shadow: shadow
    ]
    NSString(string: "M").draw(
        in: NSRect(x: size * 0.14, y: size * 0.34, width: size * 0.72, height: size * 0.38),
        withAttributes: symbolAttributes
    )

    let wordmarkAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size * 0.05, weight: .bold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.82),
        .paragraphStyle: centeredParagraph
    ]
    NSString(string: "MadCalc").draw(
        in: NSRect(x: size * 0.22, y: size * 0.075, width: size * 0.56, height: size * 0.08),
        withAttributes: wordmarkAttributes
    )

    graphicsContext.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Nie udało się zapisać PNG dla ikony.")
    }
    return data
}

let fileManager = FileManager.default
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for spec in specs {
    let destination = outputDirectory.appendingPathComponent(spec.filename)
    try renderIcon(pixelSize: spec.pixelSize).write(to: destination, options: .atomic)
}

let images = specs.map { spec in
    """
        {
          "filename" : "\(spec.filename)",
          "idiom" : "\(spec.idiom)",
          "scale" : "\(spec.scale)",
          "size" : "\(spec.size)"
        }
    """
}.joined(separator: ",\n")

let contents = """
{
  "images" : [
\(images)
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

try contents.write(to: outputDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wygenerowano ikonę MadCalc w \(outputDirectory.path)")
