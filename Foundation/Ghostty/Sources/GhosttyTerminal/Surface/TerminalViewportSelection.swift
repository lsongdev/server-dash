import CoreGraphics
import Foundation
import GhosttyKit

/// Inclusive, linear cell offsets in the visible terminal grid, independent of UTF-16.
public struct TerminalViewportSelection: Equatable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    public mutating func moveStart(to cell: Int) { start = min(cell, end) }
    public mutating func moveEnd(to cell: Int) { end = max(cell, start) }
}

/// Geometry in view points. Hosts provide the grid's padding origin explicitly.
public struct TerminalSelectionGrid: Equatable, Sendable {
    public let columns: Int
    public let rows: Int
    public let cellSize: CGSize
    public let origin: CGPoint

    public init?(metrics: TerminalGridMetrics, scale: CGFloat, origin: CGPoint = .zero) {
        guard metrics.columns > 0, metrics.rows > 0, scale > 0,
              metrics.cellWidthPixels > 0, metrics.cellHeightPixels > 0 else { return nil }
        columns = Int(metrics.columns)
        rows = Int(metrics.rows)
        cellSize = CGSize(width: CGFloat(metrics.cellWidthPixels) / scale,
                          height: CGFloat(metrics.cellHeightPixels) / scale)
        self.origin = origin
    }

    public func cell(at point: CGPoint) -> Int {
        let column = min(max(Int(floor((point.x - origin.x) / cellSize.width)), 0), columns - 1)
        let row = min(max(Int(floor((point.y - origin.y) / cellSize.height)), 0), rows - 1)
        return row * columns + column
    }

    public func rect(for cell: Int) -> CGRect {
        CGRect(x: origin.x + CGFloat(cell % columns) * cellSize.width,
               y: origin.y + CGFloat(cell / columns) * cellSize.height,
               width: cellSize.width, height: cellSize.height)
    }

    public func rects(for selection: TerminalViewportSelection) -> [CGRect] {
        let start = max(0, min(selection.start, columns * rows - 1))
        let end = max(start, min(selection.end, columns * rows - 1))
        return (start / columns ... end / columns).map { row in
            let first = max(start, row * columns)
            let last = min(end, (row + 1) * columns - 1)
            return rect(for: first).union(rect(for: last))
        }
    }
}

extension TerminalSurface {
    /// The same native word lookup used by Ghostty's own selection.
    public func wordSelection(at point: CGPoint) -> TerminalViewportSelection? {
        sendMousePos(x: Double(point.x), y: Double(point.y), modifiers: .shift)
        guard let word = quicklookWord(), !word.word.isEmpty else { return nil }
        // Ghostty reports the distance to the inclusive final cell, not a count.
        return TerminalViewportSelection(start: Int(word.offsetStart),
                                         end: Int(word.offsetStart) + Int(word.offsetLength))
    }

    /// Snap a cell on either half of a wide grapheme to its complete cell span.
    /// Compare native reads of neighboring cells and their union: adjacent
    /// identical characters read twice, while two halves of one glyph read once.
    public func characterSelection(at cell: Int) -> TerminalViewportSelection? {
        guard let metrics = size() else { return nil }
        let columns = Int(metrics.columns)
        guard columns > 0, cell >= 0, cell < columns * Int(metrics.rows) else { return nil }
        var range = TerminalViewportSelection(start: cell, end: cell)
        guard let text = readText(in: range), !text.isEmpty,
              !text.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) else {
            return range
        }
        if cell % columns > 0,
           readText(in: TerminalViewportSelection(start: cell - 1, end: cell - 1)) == text,
           readText(in: TerminalViewportSelection(start: cell - 1, end: cell)) == text {
            range.start = cell - 1
        }
        if cell % columns < columns - 1,
           readText(in: TerminalViewportSelection(start: cell + 1, end: cell + 1)) == text,
           readText(in: TerminalViewportSelection(start: cell, end: cell + 1)) == text {
            range.end = cell + 1
        }
        return range
    }

    /// Read exact cells through libghostty so Unicode and soft wraps retain native behavior.
    public func readText(in selection: TerminalViewportSelection) -> String? {
        guard let surface = rawValue, let metrics = size() else { return nil }
        let columns = Int(metrics.columns)
        let count = columns * Int(metrics.rows)
        guard selection.start >= 0, selection.end >= selection.start,
              selection.end < count else { return nil }
        func point(_ index: Int) -> ghostty_point_s {
            ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT,
                            x: UInt32(index % columns), y: UInt32(index / columns))
        }
        let range = ghostty_selection_s(top_left: point(selection.start),
                                        bottom_right: point(selection.end), rectangle: false)
        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, range, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let bytes = text.text else { return "" }
        return String(decoding: UnsafeRawBufferPointer(start: bytes, count: Int(text.text_len)), as: UTF8.self)
    }
}
