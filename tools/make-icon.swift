// Draws the app icon and writes it as an .iconset folder, and, with a
// second argument, the same shapes as an SVG.
//
// The icon is colour bars bent into an S, with a camera lens over them at
// the top right. Run it through tools/make-icon.sh, which turns the folder
// into App/AppIcon.icns.
import AppKit
import CoreGraphics

/// A colour as red, green and blue from 0 to 255.
struct Shade {
    let red: Int
    let green: Int
    let blue: Int

    init(_ hex: Int) {
        red = (hex >> 16) & 0xFF
        green = (hex >> 8) & 0xFF
        blue = hex & 0xFF
    }

    func cgColor(alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: alpha)
    }

    var svg: String { String(format: "#%02x%02x%02x", red, green, blue) }
}

/// Every measurement is in the SVG's own units: a 200 square, with the
/// tile inset from its edges and y running downwards.
enum Design {
    static let viewBox: CGFloat = 200
    static let tile = CGRect(x: 10, y: 10, width: 180, height: 180)
    static let tileCornerRadius: CGFloat = 40
    static let tileFill = Shade(0x17181D)

    /// The bars, in the order they repeat, as in the test pattern.
    static let barColours = [
        Shade(0xD9D9D9), Shade(0xD9D000), Shade(0x00C8C8), Shade(0x00C000),
        Shade(0xC800C8), Shade(0xD42020), Shade(0x2030D0),
    ]
    /// Which colour the leftmost bar takes, so the full set shows in the tile.
    static let firstBarColour = 6
    static let barCount = 10
    static let firstBarX: CGFloat = -44
    static let barSpacing: CGFloat = 26
    static let barWidth: CGFloat = 27
    /// How far right a bar has moved by the time it reaches the bottom.
    static let barDrift: CGFloat = 34
    /// The two control points' heights, which put the S in each bar.
    static let barBendTop: CGFloat = 90
    static let barBendBottom: CGFloat = 110

    static let lensCentre = CGPoint(x: 136, y: 68)
    /// The lens from the outside in: a gap in the tile's colour that lifts
    /// it off the bars, the grey ring, the dark glass and the red centre.
    static let lensRings: [(radius: CGFloat, shade: Shade)] = [
        (38, tileFill), (30, Shade(0x9EA0AD)), (24, Shade(0x110F38)), (11, Shade(0xF04C38)),
    ]
    static let glintCentre = CGPoint(x: 129, y: 61)
    static let glintRadius: CGFloat = 4
    static let glintShade = Shade(0xFFFFFF)
    static let glintOpacity: CGFloat = 0.85

    static let sizes: [(points: Int, scale: Int)] = [
        (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
    ]
}

/// One bar, from the top of the tile to the bottom.
struct Bar {
    let x: CGFloat
    let shade: Shade

    var start: CGPoint { CGPoint(x: x, y: Design.tile.minY) }
    var bendTop: CGPoint { CGPoint(x: x, y: Design.barBendTop) }
    var bendBottom: CGPoint { CGPoint(x: x + Design.barDrift, y: Design.barBendBottom) }
    var end: CGPoint { CGPoint(x: x + Design.barDrift, y: Design.tile.maxY) }

    static let all: [Bar] = (0..<Design.barCount).map { index in
        Bar(
            x: Design.firstBarX + CGFloat(index) * Design.barSpacing,
            shade: Design.barColours[(Design.firstBarColour + index) % Design.barColours.count]
        )
    }
}

// MARK: The app's icon

/// Draws the icon with the tile filling the context, square cornered.
/// macOS rounds the corners of an app's icon itself, and puts one that
/// arrives already rounded on a white plate.
func drawIcon(in context: CGContext, pixels: CGFloat) {
    let scale = pixels / Design.tile.width
    // Flip to the SVG's downward y, then map the tile onto the whole canvas.
    context.translateBy(x: 0, y: pixels)
    context.scaleBy(x: scale, y: -scale)
    context.translateBy(x: -Design.tile.minX, y: -Design.tile.minY)

    context.setFillColor(Design.tileFill.cgColor())
    context.fill(Design.tile)

    context.saveGState()
    context.clip(to: Design.tile)
    context.setLineWidth(Design.barWidth)
    for bar in Bar.all {
        context.beginPath()
        context.move(to: bar.start)
        context.addCurve(to: bar.end, control1: bar.bendTop, control2: bar.bendBottom)
        context.setStrokeColor(bar.shade.cgColor())
        context.strokePath()
    }
    context.restoreGState()

    func disc(_ centre: CGPoint, _ radius: CGFloat, _ colour: CGColor) {
        context.setFillColor(colour)
        context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    }
    for ring in Design.lensRings {
        disc(Design.lensCentre, ring.radius, ring.shade.cgColor())
    }
    disc(Design.glintCentre, Design.glintRadius, Design.glintShade.cgColor(alpha: Design.glintOpacity))
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in Design.sizes {
    let pixels = size.points * size.scale
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { continue }
    drawIcon(in: context, pixels: CGFloat(pixels))
    guard let image = context.makeImage() else { continue }
    let name = size.scale == 1 ? "icon_\(size.points)x\(size.points).png" : "icon_\(size.points)x\(size.points)@2x.png"
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    try data?.write(to: output.appendingPathComponent(name))
}

// MARK: The same icon as an SVG

func number(_ value: CGFloat) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
}

func point(_ point: CGPoint) -> String { "\(number(point.x)),\(number(point.y))" }

/// The icon on Apple's grid: the rounded tile inside a margin.
func svgIcon() -> String {
    let tile = Design.tile
    let tileRect = "<rect x=\"\(number(tile.minX))\" y=\"\(number(tile.minY))\" width=\"\(number(tile.width))\""
        + " height=\"\(number(tile.height))\" rx=\"\(number(Design.tileCornerRadius))\""
    var parts = [
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(number(Design.viewBox)) \(number(Design.viewBox))\">",
        "<title>CamTwisted</title>",
        "<defs><clipPath id=\"tile\">\(tileRect)/></clipPath></defs>",
        "\(tileRect) fill=\"\(Design.tileFill.svg)\"/>",
        "<g clip-path=\"url(#tile)\" fill=\"none\" stroke-width=\"\(number(Design.barWidth))\">",
    ]
    for bar in Bar.all {
        parts.append(
            "<path d=\"M\(point(bar.start)) C\(point(bar.bendTop)) \(point(bar.bendBottom)) \(point(bar.end))\""
                + " stroke=\"\(bar.shade.svg)\"/>"
        )
    }
    parts.append("</g>")
    func circle(_ centre: CGPoint, _ radius: CGFloat, _ attributes: String) -> String {
        "<circle cx=\"\(number(centre.x))\" cy=\"\(number(centre.y))\" r=\"\(number(radius))\" \(attributes)/>"
    }
    for ring in Design.lensRings {
        parts.append(circle(Design.lensCentre, ring.radius, "fill=\"\(ring.shade.svg)\""))
    }
    parts.append(circle(
        Design.glintCentre, Design.glintRadius,
        "fill=\"\(Design.glintShade.svg)\" fill-opacity=\"\(number(Design.glintOpacity))\""
    ))
    parts.append("</svg>")
    return parts.joined(separator: "\n") + "\n"
}

if CommandLine.arguments.count > 2 {
    try svgIcon().write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
}
