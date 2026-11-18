import Foundation

/// The System Audio Recording permission, which macOS wants for muting the other apps.
///
/// macOS has no public way to ask whether it was granted: the only public way to know is to
/// tap the other apps' sound, which asks the user. So the state comes from the system's
/// private privacy framework. When it is not there, the state is undetermined, and the app
/// does what needs no permission.
enum SystemAudio {
  enum State: String {
    case allowed, denied, undetermined
  }

  static var state: State {
    guard let preflight else { return .undetermined }
    switch preflight(service as CFString, nil) {
    case 0: return .allowed
    case 1: return .denied
    default: return .undetermined
    }
  }

  /// Has macOS ask for the permission. It asks only the first time.
  static func request() {
    guard let ask else { return }
    ask(service as CFString, nil) { _ in }
  }

  private static let service = "kTCCServiceAudioCapture"
  private static let framework = "/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC"

  private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
  private typealias Ask =
    @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

  private static let preflight: Preflight? = {
    guard let handle = dlopen(framework, RTLD_LAZY),
      let symbol = dlsym(handle, "TCCAccessPreflight")
    else { return nil }
    return unsafeBitCast(symbol, to: Preflight.self)
  }()

  private static let ask: Ask? = {
    guard let handle = dlopen(framework, RTLD_LAZY), let symbol = dlsym(handle, "TCCAccessRequest")
    else { return nil }
    return unsafeBitCast(symbol, to: Ask.self)
  }()
}
