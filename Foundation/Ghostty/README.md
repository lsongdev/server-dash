# Ghostty Swift UI integration

Vendored from [Lakr233/libghostty-spm](https://github.com/Lakr233/libghostty-spm),
tag `1.6.20260929`, commit `37557cd6db4f8af3157f90cd3ad549d1107a9ab1` (MIT).
The libghostty binary and MSDisplayLink retain their upstream versions.
Only the GhosttyKit and GhosttyTerminal products are included.

Local addition: `TerminalViewportSelection.swift` exposes viewport cell geometry,
word ranges, and text extraction for host-provided selection handles. Selection
text is read by libghostty, preserving Unicode and soft-wrap behavior. `TerminalSelectableView` supplies the in-place highlight, independent endpoint
handles, and Copy menu. The UIKit layer layout preserves child view frames.
The app uses zero grid padding and retains ownership of SSH and session state.
