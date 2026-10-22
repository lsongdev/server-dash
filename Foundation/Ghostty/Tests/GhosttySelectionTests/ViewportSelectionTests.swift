import CoreGraphics
import Testing
@testable import GhosttyTerminal

@Test func adjustEndpointsIndependently() {
    var selection = TerminalViewportSelection(start: 12, end: 18)
    selection.moveStart(to: 4)
    #expect(selection == TerminalViewportSelection(start: 4, end: 18))
    selection.moveEnd(to: 27)
    #expect(selection == TerminalViewportSelection(start: 4, end: 27))
    selection.moveStart(to: 100)
    #expect(selection.start == 27)
    selection.moveEnd(to: 0)
    #expect(selection.end == 27)
}

@Test func multilineHighlightIncludesPartialFirstAndLastRows() throws {
    let grid = try #require(TerminalSelectionGrid(metrics: TerminalGridMetrics(
        columns: 10, rows: 4, widthPixels: 300, heightPixels: 240,
        cellWidthPixels: 30, cellHeightPixels: 60), scale: 3))
    #expect(grid.rects(for: TerminalViewportSelection(start: 8, end: 21)) == [
        CGRect(x: 80, y: 0, width: 20, height: 20),
        CGRect(x: 0, y: 20, width: 100, height: 20),
        CGRect(x: 0, y: 40, width: 20, height: 20),
    ])
    #expect(grid.cell(at: CGPoint(x: -500, y: -200)) == 0)
    #expect(grid.cell(at: CGPoint(x: 500, y: 900)) == 39)
}

@Test func coordinatesRespectScaleAndPadding() throws {
    let grid = try #require(TerminalSelectionGrid(metrics: TerminalGridMetrics(
        columns: 10, rows: 4, widthPixels: 300, heightPixels: 240,
        cellWidthPixels: 30, cellHeightPixels: 60), scale: 3, origin: CGPoint(x: 5, y: 7)))
    #expect(grid.cell(at: CGPoint(x: 26, y: 28)) == 12)
    #expect(grid.rect(for: 12) == CGRect(x: 25, y: 27, width: 10, height: 20))
}

#if canImport(AppKit)
import AppKit

@Test @MainActor func nativeCellReadsPreserveUnicodeAndSoftWraps() throws {
    _ = NSApplication.shared
    let session = InMemoryTerminalSession(write: { _ in }, resize: { _ in })
    let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 500, height: 300))
    view.controller = TerminalController()
    view.configuration = TerminalSurfaceOptions(backend: .inMemory(session))
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    defer { window.contentView = nil }
    let surface = try #require(view.surface)
    session.receive("\u{1b}[2J\u{1b}[Habc中文🙂xyz\r\nsecond row")
    session.waitForPendingOutput()
    #expect(surface.readText(in: TerminalViewportSelection(start: 0, end: 2)) == "abc")
    #expect(surface.readText(in: TerminalViewportSelection(start: 3, end: 8)) == "中文🙂")
    #expect(surface.characterSelection(at: 3) == TerminalViewportSelection(start: 3, end: 4))
    #expect(surface.characterSelection(at: 4) == TerminalViewportSelection(start: 3, end: 4))
    #expect(surface.characterSelection(at: 8) == TerminalViewportSelection(start: 7, end: 8))
    let columns = try #require(surface.size()).columns
    #expect(surface.readText(in: TerminalViewportSelection(start: Int(columns), end: Int(columns) + 5)) == "second")
    session.receive("\u{1b}[2J\u{1b}[H中中🙂🙂")
    session.waitForPendingOutput()
    #expect(surface.characterSelection(at: 2) == TerminalViewportSelection(start: 2, end: 3))
    #expect(surface.characterSelection(at: 5) == TerminalViewportSelection(start: 4, end: 5))
    session.receive("\u{1b}[2J\u{1b}[H" + String(repeating: "a", count: Int(columns) - 1) + "XYZ")
    session.waitForPendingOutput()
    #expect(surface.readText(in: TerminalViewportSelection(start: Int(columns) - 2, end: Int(columns) + 1)) == "aXYZ")
}
#endif
