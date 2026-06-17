import SwiftUI

// One name for the platform's representable + font so the editor backend
// reads the same on macOS (AppKit) and iOS (UIKit).
#if canImport(UIKit)
  import UIKit
  typealias PlatformViewRepresentable = UIViewRepresentable
  typealias PlatformFont = UIFont
  typealias PlatformColor = UIColor
  typealias PlatformTextView = UITextView
  typealias FontTraits = UIFontDescriptor.SymbolicTraits

  extension FontTraits {
    static let boldTrait = traitBold
    static let italicTrait = traitItalic
  }

  extension PlatformColor {
    /// High-contrast body text and the page it sits on. Both adapt to light
    /// and dark mode so the editor is always readable.
    static var editorText: PlatformColor { .label }
    static var editorBackground: PlatformColor { .systemBackground }
  }
#elseif canImport(AppKit)
  import AppKit
  typealias PlatformViewRepresentable = NSViewRepresentable
  typealias PlatformFont = NSFont
  typealias PlatformColor = NSColor
  typealias PlatformTextView = NSTextView
  typealias FontTraits = NSFontDescriptor.SymbolicTraits

  extension FontTraits {
    static let boldTrait = bold
    static let italicTrait = italic
  }

  extension PlatformColor {
    /// High-contrast body text and the page it sits on. Both adapt to light
    /// and dark mode so the editor is always readable.
    static var editorText: PlatformColor { .labelColor }
    static var editorBackground: PlatformColor { .textBackgroundColor }
  }
#endif

extension PlatformTextView {
  // UITextView.textStorage is non-optional; NSTextView.textStorage is optional.
  // Declaring the return as Optional? lets shared code bind both uniformly.
  var optionalTextStorage: NSTextStorage? { textStorage }
}

extension PlatformFont {
  var traits: FontTraits { fontDescriptor.symbolicTraits }

  /// Same face and size with exactly `traits`. Falls back to `self` when the
  /// face has no variant for the requested traits.
  func with(traits: FontTraits) -> PlatformFont {
    #if canImport(UIKit)
      guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
      return PlatformFont(descriptor: descriptor, size: pointSize)
    #elseif canImport(AppKit)
      let descriptor = fontDescriptor.withSymbolicTraits(traits)
      return PlatformFont(descriptor: descriptor, size: pointSize) ?? self
    #endif
  }

  func toggling(_ trait: FontTraits) -> PlatformFont {
    with(traits: traits.symmetricDifference(trait))
  }
}
