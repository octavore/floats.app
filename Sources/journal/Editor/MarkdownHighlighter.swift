import Foundation
import SwiftTreeSitter
import TreeSitterMarkdown
import TreeSitterMarkdownInline

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// Derives the journal's formatting from the text *as Markdown* rather than
/// from stored rich-text attributes. The block grammar finds headings and code
/// blocks; the inline grammar finds emphasis and code spans within each
/// paragraph's content. The Markdown source stays the single source of truth
/// for how the document looks.
///
/// tree-sitter-markdown is a "split" grammar: the block parser leaves inline
/// content unparsed in `inline` nodes, which we re-parse with the inline parser.
///
/// The highlighter is the text storage's `NSTextStorageDelegate`. On each user
/// edit `didProcessEditing` hands us the exact edited range and length delta —
/// far better than reconstructing the edit by diffing — so we feed tree-sitter a
/// precise `InputEdit`, reparse *incrementally* (reusing the untouched
/// subtrees), and restyle only the paragraphs the parse says actually changed.
///
/// Incremental tree reuse previously collapsed to an empty `(document)` under
/// release optimization. We keep a safety net: if a reparse degenerates that way
/// over non-empty text, we throw the tree away and parse from scratch, so the
/// styling is always correct even if we occasionally pay for a full parse.
///
/// SwiftTreeSitter parses in UTF-16LE, so every byte offset tree-sitter reports
/// is a UTF-16 *byte* offset — exactly two per `NSString`/`NSRange` UTF-16 code
/// unit, which is why the range conversions here halve byte offsets.
@MainActor
final class MarkdownHighlighter: NSObject {
  private let block = Parser()
  private let inline = Parser()

  /// The parse tree for the text currently in the storage, reused across edits
  /// for incremental parsing. Nil until the first parse, and reset whenever a
  /// reparse degenerates and we fall back to a fresh parse.
  private var tree: MutableTree?

  /// The text as of the last successful parse. `didProcessEditing` only gives us
  /// the post-edit string, so we keep the pre-edit text to compute the *old* end
  /// point of an `InputEdit` (row/column tree-sitter needs alongside the bytes).
  private var lastString: NSString = ""

  /// UTF-16 length of the text currently being styled, so `nsRange` can clamp
  /// node ranges that reach past the document (tree-sitter sometimes reports a
  /// block's range out to a trailing position) instead of throwing.
  private var length = 0

  override init() {
    super.init()
    do {
      try block.setLanguage(Language(tree_sitter_markdown()))
      try inline.setLanguage(Language(tree_sitter_markdown_inline()))
    } catch {
      print("MarkdownHighlighter: setLanguage failed: \(error)")
    }
  }

  // MARK: Entry points

  /// Full reparse and restyle of the entire document. Used for the initial
  /// render and any programmatic whole-document replacement. Safe to call from
  /// outside an edit transaction — it brackets its own begin/endEditing.
  func highlight(_ storage: NSTextStorage) {
    let ns = storage.string as NSString
    guard let root = freshParse(ns) else { return }
    storage.beginEditing()
    restyle(ranges: [NSRange(location: 0, length: ns.length)], root: root, source: ns, in: storage)
    storage.endEditing()
  }

  /// Incrementally reparses and restyles `storage` for a single character edit.
  /// `editedRange` is in the post-edit text; `delta` is the change in length
  /// (`changeInLength`). Must run inside the storage's edit processing: it
  /// mutates attributes directly, without begin/endEditing.
  func applyEdit(editedRange: NSRange, delta: Int, to storage: NSTextStorage) {
    let new = storage.string as NSString

    // No baseline tree, or a whole-document replacement (e.g. setAttributedString):
    // a fresh parse is both simpler and what incremental would reduce to.
    let isWholeDoc = editedRange.location == 0 && editedRange.length == new.length
    guard let old = tree, !isWholeDoc else {
      fullRestyle(new, in: storage)
      return
    }

    // Tell the cached tree exactly what changed, then reparse reusing it. The
    // start point is shared by both texts (the prefix is unchanged); the old end
    // point must come from the pre-edit text, the new end point from the current.
    let oldStr = lastString
    let start = editedRange.location
    let newEnd = editedRange.location + editedRange.length
    let oldEnd = newEnd - delta
    old.edit(
      InputEdit(
        startByte: start * 2, oldEndByte: oldEnd * 2, newEndByte: newEnd * 2,
        startPoint: point(at: start, in: oldStr),
        oldEndPoint: point(at: oldEnd, in: oldStr),
        newEndPoint: point(at: newEnd, in: new)))

    length = new.length
    guard let newTree = block.parse(tree: old, readBlock: readBlock(for: new)),
      let root = newTree.rootNode
    else { return }

    // Safety net: an incremental reparse that collapses to an empty document
    // over non-empty text is the documented release-mode corruption. Discard it
    // and parse from scratch so styling stays correct.
    if root.childCount == 0, new.length > 0 {
      fullRestyle(new, in: storage)
      return
    }

    // Ranges whose syntax changed. tree-sitter's contract is
    // changed(old_tree: edited, new_tree: reparsed); `old` is now the edited
    // tree, so it is the receiver and `newTree` the argument.
    var targets = old.changedRanges(from: newTree).map { nsRange($0.bytes) }
    tree = newTree
    lastString = new

    // Always restyle the edited paragraph, unioned with any structural changes,
    // each expanded to whole paragraphs so block styling aligns to line bounds.
    targets.append(editedRange)
    let expanded = paragraphs(covering: targets, in: new)
    restyle(ranges: expanded, root: root, source: new, in: storage)
  }

  /// Parses `ns` from scratch and restyles the whole document. The shared
  /// fallback for the initial render, whole-document replacement, and a
  /// degenerate incremental parse.
  private func fullRestyle(_ ns: NSString, in storage: NSTextStorage) {
    guard let root = freshParse(ns) else { return }
    restyle(ranges: [NSRange(location: 0, length: ns.length)], root: root, source: ns, in: storage)
  }

  /// Parses `ns` with no tree reuse, caches the result as the new baseline, and
  /// returns the root node. Returns nil only if the parser yields nothing.
  private func freshParse(_ ns: NSString) -> Node? {
    length = ns.length
    guard let newTree = block.parse(tree: nil as Tree?, readBlock: readBlock(for: ns)),
      let root = newTree.rootNode
    else { return nil }
    tree = newTree
    lastString = ns
    return root
  }

  /// Feeds tree-sitter the requested slice of `ns` as UTF-16LE bytes pulled
  /// straight from the live string — `NSString` is already UTF-16 internally, so
  /// we copy only the few-KB chunk tree-sitter asks for rather than the whole
  /// document on every parse. `byteOffset` is a UTF-16 byte offset (two per code
  /// unit). SwiftTreeSitter copies each returned chunk into its own buffer, so
  /// the `Data` we hand back only needs to outlive the call.
  private func readBlock(for ns: NSString) -> Parser.ReadBlock {
    let unitCount = ns.length
    let chunkUnits = 2048
    return { byteOffset, _ in
      let start = byteOffset / 2
      guard start >= 0, start < unitCount else { return nil }
      let count = min(chunkUnits, unitCount - start)
      var buffer = [unichar](repeating: 0, count: count)
      ns.getCharacters(&buffer, range: NSRange(location: start, length: count))
      return buffer.withUnsafeBytes { Data($0) }
    }
  }

  // MARK: Restyling

  /// Resets the given ranges to the body style, then re-applies the styling the
  /// parse tree implies for any block that intersects them. The tree walk prunes
  /// subtrees that fall entirely outside `ranges`, so an incremental edit only
  /// touches the paragraphs that changed.
  private func restyle(ranges: [NSRange], root: Node, source ns: NSString, in storage: NSTextStorage) {
    for range in ranges where range.length > 0 {
      storage.setAttributes(TextStyle.body.attributes, range: range)
    }
    styleBlock(root, in: storage, source: ns as String, targets: ranges)
  }

  // MARK: Block level

  private func styleBlock(
    _ node: Node, in storage: NSTextStorage, source: String, targets: [NSRange]
  ) {
    let range = nsRange(node.byteRange)
    guard intersects(range, targets) else { return }

    switch node.nodeType ?? "" {
    case "atx_heading", "setext_heading":
      apply(headingStyle(for: node), to: range, in: storage)
    case "fenced_code_block", "indented_code_block":
      applyCode(to: range, in: storage)
      return  // code is verbatim; don't descend for inline emphasis
    case "inline":
      styleInline(node, range: range, in: storage, source: source)
      return
    default:
      break
    }

    // recurse into children to find nested blocks and inlines
    for index in 0..<node.childCount {
      if let child = node.child(at: index) {
        styleBlock(child, in: storage, source: source, targets: targets)
      }
    }
  }

  /// Whether `range` overlaps any range we are restyling. The document root
  /// spans everything and so always passes, letting the walk descend; blocks
  /// outside the changed paragraphs are pruned.
  private func intersects(_ range: NSRange, _ targets: [NSRange]) -> Bool {
    targets.contains { NSIntersectionRange(range, $0).length > 0 }
  }

  /// Title for a level-1 heading, otherwise the heading style.
  private func headingStyle(for node: Node) -> TextStyle {
    for index in 0..<node.childCount {
      switch node.child(at: index)?.nodeType ?? "" {
      case "atx_h1_marker", "setext_h1_underline": return .title
      default: continue
      }
    }
    return .heading
  }

  // MARK: Inline level

  private func styleInline(
    _ inlineNode: Node, range: NSRange, in storage: NSTextStorage, source: String
  ) {
    let substring = (source as NSString).substring(with: range)
    guard !substring.isEmpty else { return }
    guard let tree = inline.parse(substring), let root = tree.rootNode
    else { return }
    walkInline(root, base: inlineNode.byteRange.lowerBound, in: storage)
  }

  private func walkInline(_ node: Node, base: UInt32, in storage: NSTextStorage) {
    let absolute = (node.byteRange.lowerBound + base)..<(node.byteRange.upperBound + base)
    switch node.nodeType ?? "" {
    case "strong_emphasis":
      addTrait(.boldTrait, to: nsRange(absolute), in: storage)
    case "emphasis":
      addTrait(.italicTrait, to: nsRange(absolute), in: storage)
    case "code_span":
      applyCode(to: nsRange(absolute), in: storage)
    case "strikethrough":
      storage.addAttribute(
        .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange(absolute))
    default:
      break
    }
    for index in 0..<node.childCount {
      if let child = node.child(at: index) {
        walkInline(child, base: base, in: storage)
      }
    }
  }

  // MARK: Attribute application

  /// Sets a block style's font, paragraph, and color across `range`.
  private func apply(_ style: TextStyle, to range: NSRange, in storage: NSTextStorage) {
    storage.addAttributes(style.attributes, range: range)
  }

  /// Unions a symbolic trait onto whatever font each run already carries, so a
  /// heading stays heading-sized when its words are also `**bold**`.
  private func addTrait(_ trait: FontTraits, to range: NSRange, in storage: NSTextStorage) {
    storage.enumerateAttribute(.font, in: range) { value, runRange, _ in
      let current = value as? PlatformFont ?? TextStyle.body.font
      storage.addAttribute(
        .font, value: current.with(traits: current.traits.union(trait)), range: runRange)
    }
  }

  private func applyCode(to range: NSRange, in storage: NSTextStorage) {
    storage.enumerateAttribute(.font, in: range) { value, runRange, _ in
      let size = (value as? PlatformFont ?? TextStyle.body.font).pointSize
      storage.addAttribute(
        .font, value: PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular),
        range: runRange)
    }
  }

  // MARK: Range conversion

  /// Converts a tree-sitter UTF-16 byte range into an `NSRange` (UTF-16 code
  /// units). Each code unit is two bytes, so the bounds halve cleanly; both are
  /// clamped to the current length so a node reaching past the document yields a
  /// valid (possibly empty) range rather than throwing when it's applied.
  private func nsRange(_ byteRange: Range<UInt32>) -> NSRange {
    let lower = min(Int(byteRange.lowerBound) / 2, length)
    let upper = min(Int(byteRange.upperBound) / 2, length)
    return NSRange(location: lower, length: upper - lower)
  }

  /// Expands each range to whole paragraphs, so block styling (headings, code
  /// fences, spacing) is recomputed against entire lines. Overlapping results
  /// are harmless — restyle just re-applies the same attributes.
  private func paragraphs(covering ranges: [NSRange], in ns: NSString) -> [NSRange] {
    ranges.map { r in
      let location = min(r.location, ns.length)
      let clamped = NSRange(location: location, length: min(r.length, ns.length - location))
      return ns.paragraphRange(for: clamped)
    }
  }

  /// Row, and column measured in UTF-16 bytes, of a UTF-16 offset — the
  /// line-relative position tree-sitter wants alongside the byte offsets.
  private func point(at offset: Int, in string: NSString) -> Point {
    var row = 0
    var lineStart = 0
    var i = 0
    let bounded = min(offset, string.length)
    while i < bounded {
      if string.character(at: i) == 0x0A {  // newline
        row += 1
        lineStart = i + 1
      }
      i += 1
    }
    return Point(row: row, column: (bounded - lineStart) * 2)
  }
}

extension MarkdownHighlighter: @preconcurrency NSTextStorageDelegate {
  /// The single place user edits trigger restyling. Fires after the storage
  /// applies an edit; `.editedCharacters` distinguishes a text change from the
  /// attribute changes we make here (which would otherwise recurse).
  func textStorage(
    _ textStorage: NSTextStorage,
    didProcessEditing editedMask: NSTextStorageEditActions,
    range editedRange: NSRange,
    changeInLength delta: Int
  ) {
    guard editedMask.contains(.editedCharacters) else { return }
    applyEdit(editedRange: editedRange, delta: delta, to: textStorage)
  }
}
