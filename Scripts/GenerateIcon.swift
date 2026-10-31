import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Original radar artwork for 探す, drawn without text or platform-owned symbols.
// Keep the source square and opaque; iOS applies the home-screen icon mask.
let side = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let context = CGContext(
  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
  space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
let colors =
  [
    CGColor(red: 0.015, green: 0.32, blue: 0.25, alpha: 1),
    CGColor(red: 0.04, green: 0.65, blue: 0.43, alpha: 1),
  ] as CFArray
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
context.drawLinearGradient(
  gradient, start: CGPoint(x: 512, y: 0), end: CGPoint(x: 512, y: 1024),
  options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

let center = CGPoint(x: 512, y: 512)
context.setLineWidth(30)
for (radius, opacity) in [(340.0, 0.24), (218.0, 0.52)] {
  context.setStrokeColor(CGColor(gray: 1, alpha: opacity))
  context.strokeEllipse(
    in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

let sweep = CGMutablePath()
sweep.move(to: center)
sweep.addArc(
  center: center, radius: 340, startAngle: .pi / 6, endAngle: .pi / 3, clockwise: false)
sweep.closeSubpath()
context.setFillColor(CGColor(red: 0.75, green: 1, blue: 0.86, alpha: 0.14))
context.addPath(sweep)
context.fillPath()

let target = CGPoint(x: 512 + 218 / sqrt(2), y: 512 + 218 / sqrt(2))
context.setFillColor(CGColor(gray: 1, alpha: 1))
context.fillEllipse(in: CGRect(x: 486, y: 486, width: 52, height: 52))
context.setFillColor(CGColor(red: 0.75, green: 1, blue: 0.84, alpha: 1))
context.fillEllipse(in: CGRect(x: target.x - 43, y: target.y - 43, width: 86, height: 86))

let artwork = context.makeImage()!

func writePNG(_ image: CGImage, to url: URL) throws {
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  let destination = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  precondition(CGImageDestinationFinalize(destination))
}

let output = URL(fileURLWithPath: "AndroidFind/Resources/Assets.xcassets/AppIcon.appiconset")
try writePNG(artwork, to: output.appendingPathComponent("AppIcon.png"))
try Data(
  """
  {"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
  """
  .utf8
)
.write(to: output.appendingPathComponent("Contents.json"))

// A small home-screen-style preview for visual review. The asset above remains unmasked.
let preview = CGContext(
  data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 256 * 4,
  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
preview.addPath(
  CGPath(
    roundedRect: CGRect(x: 0, y: 0, width: 256, height: 256), cornerWidth: 57,
    cornerHeight: 57, transform: nil))
preview.clip()
preview.interpolationQuality = .high
preview.draw(artwork, in: CGRect(x: 0, y: 0, width: 256, height: 256))
try writePNG(preview.makeImage()!, to: URL(fileURLWithPath: "Artifacts/Sagasu-Icon-Preview.png"))
