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
/// Everything on the per-keystroke path is kept off the document's length:
///  - We read characters through `storage.mutableString`, a live non-copying
///    proxy, instead of `storage.string`, which snapshots the whole document.
///  - tree-sitter is fed a few-KB chunk at a time from that proxy, so an
///    incremental reparse only reads the regions near the edit.
///  - The row/column `Point`s an `InputEdit` needs come from a line-start index
///    maintained incrementally, so we never rescan the document counting
///    newlines (which, three times per keystroke, dominated large-document cost).
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

  /// UTF-16 offsets at which each line starts (`[0]` for an empty document), so
  /// `point(at:)` can find a row by binary search instead of scanning the whole
  /// document. Maintained incrementally across edits and rebuilt on a full parse.
  private var lineStarts: [Int] = [0]

  /// UTF-16 length of the text the index and styling currently describe, so
  /// `nsRange` can clamp node ranges that reach past the document (tree-sitter
  /// sometimes reports a block's range out to a trailing position).
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
    guard let root = freshParse(storage) else { return }
    storage.beginEditing()
    restyle(
      ranges: [NSRange(location: 0, length: storage.length)], root: root,
      source: storage.mutableString, in: storage)
    storage.endEditing()
  }

  /// Incrementally reparses and restyles `storage` for a single character edit.
  /// `editedRange` is in the post-edit text; `delta` is the change in length
  /// (`changeInLength`). Must run inside the storage's edit processing: it
  /// mutates attributes directly, without begin/endEditing.
  func applyEdit(editedRange: NSRange, delta: Int, to storage: NSTextStorage) {
    let newLength = storage.length

    // No baseline tree, or a whole-document replacement (e.g. setAttributedString):
    // a fresh parse is both simpler and what incremental would reduce to.
    let isWholeDoc = editedRange.location == 0 && editedRange.length == newLength
    guard let old = tree, !isWholeDoc else {
      fullRestyle(storage)
      return
    }

    let start = editedRange.location
    let newEnd = editedRange.location + editedRange.length
    let oldEnd = newEnd - delta

    // The start point is shared by both texts (the prefix is unchanged); the old
    // end point must be read against the pre-edit line index, so compute both
    // before advancing the index. The byte offsets are authoritative for
    // tree-sitter; the points keep its column-sensitive scanner honest.
    let startPoint = point(at: start)
    let oldEndPoint = point(at: oldEnd)
    updateLineStarts(start: start, oldEnd: oldEnd, newEnd: newEnd, delta: delta, in: storage)
    length = newLength
    let newEndPoint = point(at: newEnd)

    old.edit(
      InputEdit(
        startByte: start * 2, oldEndByte: oldEnd * 2, newEndByte: newEnd * 2,
        startPoint: startPoint, oldEndPoint: oldEndPoint, newEndPoint: newEndPoint))

    guard let newTree = block.parse(tree: old, readBlock: readBlock(for: storage)),
      let root = newTree.rootNode
    else {
      tree = nil  // force a clean full parse next time
      return
    }

    // Safety net: an incremental reparse that collapses to an empty document
    // over non-empty text is the documented release-mode corruption. Discard it
    // and parse from scratch so styling stays correct.
    if root.childCount == 0, newLength > 0 {
      fullRestyle(storage)
      return
    }

    // Ranges whose syntax changed. tree-sitter's contract is
    // changed(old_tree: edited, new_tree: reparsed); `old` is now the edited
    // tree, so it is the receiver and `newTree` the argument.
    var targets = old.changedRanges(from: newTree).map { nsRange($0.bytes) }
    tree = newTree

    // Always restyle the edited paragraph, unioned with any structural changes,
    // each expanded to whole paragraphs so block styling aligns to line bounds.
    targets.append(editedRange)
    let source = storage.mutableString
    restyle(ranges: paragraphs(covering: targets, in: source), root: root, source: source, in: storage)
  }

  /// Parses `storage` from scratch and restyles the whole document. The shared
  /// fallback for the initial render, whole-document replacement, and a
  /// degenerate incremental parse.
  private func fullRestyle(_ storage: NSTextStorage) {
    guard let root = freshParse(storage) else { return }
    restyle(
      ranges: [NSRange(location: 0, length: storage.length)], root: root,
      source: storage.mutableString, in: storage)
  }

  /// Parses `storage` with no tree reuse, rebuilds the line index as the new
  /// baseline, and returns the root node. Returns nil only if the parser yields
  /// nothing.
  private func freshParse(_ storage: NSTextStorage) -> Node? {
    rebuildLineStarts(storage)
    guard let newTree = block.parse(tree: nil as Tree?, readBlock: readBlock(for: storage)),
      let root = newTree.rootNode
    else {
      tree = nil
      return nil
    }
    tree = newTree
    return root
  }

  /// Feeds tree-sitter the requested slice of the document as UTF-16LE bytes
  /// pulled straight from `storage.mutableString` — a live proxy, so we copy
  /// only the few-KB chunk tree-sitter asks for rather than snapshotting the
  /// whole document on every parse. `byteOffset` is a UTF-16 byte offset (two
  /// per code unit). SwiftTreeSitter copies each returned chunk into its own
  /// buffer, so the `Data` we hand back only needs to outlive the call.
  private func readBlock(for storage: NSTextStorage) -> Parser.ReadBlock {
    let string = storage.mutableString
    let unitCount = string.length
    let chunkUnits = 2048
    return { byteOffset, _ in
      let start = byteOffset / 2
      guard start >= 0, start < unitCount else { return nil }
      let count = min(chunkUnits, unitCount - start)
      var buffer = [unichar](repeating: 0, count: count)
      string.getCharacters(&buffer, range: NSRange(location: start, length: count))
      return buffer.withUnsafeBytes { Data($0) }
    }
  }

  // MARK: Line index

  /// Recomputes every line start by scanning the document once. Used only on a
  /// full parse, never per keystroke.
  private func rebuildLineStarts(_ storage: NSTextStorage) {
    let string = storage.mutableString
    let n = string.length
    var starts: [Int] = [0]
    if n > 0 {
      var buffer = [unichar](repeating: 0, count: n)
      string.getCharacters(&buffer, range: NSRange(location: 0, length: n))
      for i in 0..<n where buffer[i] == 0x0A { starts.append(i + 1) }
    }
    lineStarts = starts
    length = n
  }

  /// Splices the line index for an edit that replaced `start..<oldEnd` with the
  /// text now occupying `start..<newEnd`: keep the starts up to `start`, add one
  /// per newline in the inserted run, then shift the starts past the edit by
  /// `delta`. O(line count), versus rescanning the whole document.
  private func updateLineStarts(
    start: Int, oldEnd: Int, newEnd: Int, delta: Int, in storage: NSTextStorage
  ) {
    var result: [Int] = []
    result.reserveCapacity(lineStarts.count + 2)
    for line in lineStarts where line <= start { result.append(line) }
    if newEnd > start {
      let count = newEnd - start
      var buffer = [unichar](repeating: 0, count: count)
      storage.mutableString.getCharacters(&buffer, range: NSRange(location: start, length: count))
      for i in 0..<count where buffer[i] == 0x0A { result.append(start + i + 1) }
    }
    for line in lineStarts where line > oldEnd { result.append(line + delta) }
    lineStarts = result
  }

  /// Row, and column measured in UTF-16 bytes, of a UTF-16 offset — found by
  /// binary search over the line index, the line-relative position tree-sitter
  /// wants alongside the byte offsets.
  private func point(at offset: Int) -> Point {
    let bounded = max(0, min(offset, length))
    var low = 0
    var high = lineStarts.count - 1
    var row = 0
    while low <= high {
      let mid = (low + high) / 2
      if lineStarts[mid] <= bounded {
        row = mid
        low = mid + 1
      } else {
        high = mid - 1
      }
    }
    return Point(row: row, column: (bounded - lineStarts[row]) * 2)
  }

  // MARK: Restyling

  /// Resets the given ranges to the body style, then re-applies the styling the
  /// parse tree implies for any block that intersects them. The tree walk prunes
  /// subtrees that fall entirely outside `ranges`, so an incremental edit only
  /// touches the paragraphs that changed.
  private func restyle(
    ranges: [NSRange], root: Node, source: NSString, in storage: NSTextStorage
  ) {
    for range in ranges where range.length > 0 {
      storage.setAttributes(TextStyle.body.attributes, range: range)
    }
    styleBlock(root, in: storage, source: source, targets: ranges)
  }

  // MARK: Block level

  private func styleBlock(
    _ node: Node, in storage: NSTextStorage, source: NSString, targets: [NSRange]
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
    _ inlineNode: Node, range: NSRange, in storage: NSTextStorage, source: NSString
  ) {
    let substring = source.substring(with: range)
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
