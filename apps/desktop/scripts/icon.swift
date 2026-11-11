// Draws the app icons into Support/: AppIcon.icns for production, and
// AppIconDevelopment.icns, marked DEV, for development. Run it after changing the design:
//
//   swift scripts/icon.swift

import AppKit

let support = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  .deletingLastPathComponent().appendingPathComponent("Support")

/// Heights of the waveform's bars, as a share of the tallest.
let bars: [CGFloat] = [0.28, 0.55, 0.82, 1, 0.68, 0.42, 0.22]

/// Draws the icon on a 1024-point canvas, following the macOS icon grid.
func draw(isDevelopment: Bool) {
  let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
  let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

  NSGraphicsContext.saveGraphicsState()
  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
  shadow.shadowOffset = NSSize(width: 0, height: -10)
  shadow.shadowBlurRadius = 24
  shadow.set()
  NSColor.black.setFill()
  shape.fill()
  NSGraphicsContext.restoreGraphicsState()

  NSGradient(starting: NSColor(white: 0.2, alpha: 1), ending: NSColor(white: 0.07, alpha: 1))?
    .draw(in: shape, angle: -90)

  let ink = isDevelopment ? NSColor(red: 1, green: 0.72, blue: 0.2, alpha: 1) : NSColor.white
  ink.setFill()
  let width: CGFloat = 46
  let gap: CGFloat = 38
  let tallest: CGFloat = isDevelopment ? 380 : 440
  let center = tile.midY + (isDevelopment ? 70 : 0)
  let left = tile.midX - (CGFloat(bars.count) * width + CGFloat(bars.count - 1) * gap) / 2
  for (index, share) in bars.enumerated() {
    let height = tallest * share
    let bar = NSRect(
      x: left + CGFloat(index) * (width + gap), y: center - height / 2, width: width,
      height: height)
    NSBezierPath(roundedRect: bar, xRadius: width / 2, yRadius: width / 2).fill()
  }

  if isDevelopment {
    let label = NSAttributedString(
      string: "DEV",
      attributes: [
        .font: NSFont.systemFont(ofSize: 150, weight: .heavy),
        .foregroundColor: ink,
        .kern: 14,
      ])
    let size = label.size()
    label.draw(at: NSPoint(x: tile.midX - size.width / 2, y: tile.minY + 70))
  }
}

func png(pixels: Int, isDevelopment: Bool) -> Data {
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  let scale = NSAffineTransform()
  scale.scale(by: CGFloat(pixels) / 1024)
  scale.concat()
  draw(isDevelopment: isDevelopment)
  NSGraphicsContext.restoreGraphicsState()
  return bitmap.representation(using: .png, properties: [:])!
}

for (name, isDevelopment) in [("AppIcon", false), ("AppIconDevelopment", true)] {
  let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).iconset")
  try? FileManager.default.removeItem(at: iconset)
  try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
  for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
      let file = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
      try png(pixels: points * scale, isDevelopment: isDevelopment)
        .write(to: iconset.appendingPathComponent(file))
    }
  }

  let iconutil = Process()
  iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
  iconutil.arguments = [
    "-c", "icns", iconset.path, "-o", support.appendingPathComponent("\(name).icns").path,
  ]
  try iconutil.run()
  iconutil.waitUntilExit()
  guard iconutil.terminationStatus == 0 else { exit(1) }
  print("wrote Support/\(name).icns")
}
