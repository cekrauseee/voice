/// Writes a log record as `message key=value key="quoted value"`.
///
/// The message says what happened, as a short lowercase phrase. Everything that varies
/// goes in the fields. The development tools read this form back: see docs/logging.md.
public func logLine(_ message: String, _ fields: KeyValuePairs<String, Any> = [:]) -> String {
  fields.reduce(into: message) { line, field in
    let value = "\(field.value)"
    let isPlain = !value.isEmpty && !value.contains { $0.isWhitespace || $0 == "\"" || $0 == "=" }
    line += " \(field.key)=" + (isPlain ? value : quoted(value))
  }
}

private func quoted(_ value: String) -> String {
  let escaped = value.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
  return "\"\(escaped.replacing("\n", with: "\\n"))\""
}
