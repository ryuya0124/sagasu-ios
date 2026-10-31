import Foundation

enum GoogleAccountIdentity {
  static func normalized(_ value: Any?) -> String? {
    guard let value = value as? String else { return nil }
    let email = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let parts = email.split(separator: "@", omittingEmptySubsequences: false)
    guard email.count <= 254, parts.count == 2, !parts[0].isEmpty,
      parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
      email.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil
    else { return nil }
    return email
  }
}
