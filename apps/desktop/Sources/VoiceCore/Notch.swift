/// The notch at the top of a screen that has one, where the camera is.
public struct Notch: Equatable, Sendable {
  /// From the left edge of the screen.
  public let minX: Double
  public let width: Double
  public let height: Double

  public var midX: Double { minX + width / 2 }

  /// The notch between the areas of the menu bar on either side of it, as tall as the
  /// part of the screen it takes from the top. Nil on a screen without a notch.
  public init?(screenWidth: Double, leftWidth: Double, rightWidth: Double, height: Double) {
    let width = screenWidth - leftWidth - rightWidth
    guard width > 0, height > 0 else { return nil }
    self.minX = leftWidth
    self.width = width
    self.height = height
  }
}
