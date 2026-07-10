import AppKit
import SwiftUI

typealias PlatformViewRepresentable = NSViewRepresentable
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
typealias PlatformTextView = NSTextView
typealias FontTraits = NSFontDescriptor.SymbolicTraits
typealias FontDesign = NSFontDescriptor.SystemDesign

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

extension PlatformFont {
  var traits: FontTraits { fontDescriptor.symbolicTraits }

  /// Same face and size with exactly `traits`. Falls back to `self` when the
  /// face has no variant for the requested traits.
  func with(traits: FontTraits) -> PlatformFont {
    let descriptor = fontDescriptor.withSymbolicTraits(traits)
    return PlatformFont(descriptor: descriptor, size: pointSize) ?? self
  }

  func toggling(_ trait: FontTraits) -> PlatformFont {
    with(traits: traits.symmetricDifference(trait))
  }

  /// A system font of the given size and weight in one of the built-in system
  /// *designs* (default, serif, rounded, monospaced). Falls back to the plain
  /// system font if the design has no variant at this size/weight.
  static func floats(ofSize size: CGFloat, weight: Weight, design: FontDesign) -> PlatformFont {
    let base = systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
    return PlatformFont(descriptor: descriptor, size: size) ?? base
  }
}
