import Foundation

/// What this build of the app is. The development and production builds differ in name and
/// identifier, so macOS keeps their permissions and settings apart.
enum AppInfo {
  static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Voice"
  static let identifier = Bundle.main.bundleIdentifier ?? "eu.cekrause.voice"
  static let version =
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

  #if DEBUG
    static let isDevelopment = true
  #else
    static let isDevelopment = false
  #endif
}
