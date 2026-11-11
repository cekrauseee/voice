import Observation

/// Calls `onChange` with the current value, and again whenever the observed value changes.
@MainActor
func track<Value>(
  _ value: @escaping @MainActor @Sendable () -> Value,
  onChange: @escaping @MainActor @Sendable (Value) -> Void
) {
  let current = withObservationTracking(value) {
    Task { @MainActor in track(value, onChange: onChange) }
  }
  onChange(current)
}
