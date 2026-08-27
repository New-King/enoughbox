import AppKit
import SwiftUI

extension DesignTokens {
  static var current: DesignTokens {
    tokens(for: AppearanceMode.stored.effectiveColorScheme)
  }
}

extension Color {
  var nsColor: NSColor {
    NSColor(self)
  }
}
