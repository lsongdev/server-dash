#if canImport(UIKit) && !targetEnvironment(macCatalyst)
import UIKit

/// In-place touch selection with independent start/end handles and the system Copy menu.
/// The host must use zero window padding or override `selectionGridOrigin`.
@available(iOS 16.0, *)
@MainActor
open class TerminalSelectableView: UITerminalView {
    open var selectionGridOrigin: CGPoint { .zero }

    private lazy var selectionPress = UILongPressGestureRecognizer(target: self, action: #selector(selectText(_:)))
    private let highlight = SelectionHighlightView()
    private let startHandle = SelectionHandle(isStart: true)
    private let endHandle = SelectionHandle(isStart: false)
    private var selection: TerminalViewportSelection?
    private var selectedText: String?
    private var selectionGrid: TerminalSelectionGrid?
    private var pressRange: TerminalViewportSelection?
    private var handleAnchor = CGPoint.zero
    private var handleTouch = CGPoint.zero
    private var lastValidation: TimeInterval = 0
    private lazy var copyMenu = UIEditMenuInteraction(delegate: self)

    public override init(frame: CGRect) {
        super.init(frame: frame)
        highlight.isUserInteractionEnabled = false
        addSubview(highlight)
        addSubview(startHandle)
        addSubview(endHandle)
        startHandle.isHidden = true
        endHandle.isHidden = true
        startHandle.pan.addTarget(self, action: #selector(dragHandle(_:)))
        endHandle.pan.addTarget(self, action: #selector(dragHandle(_:)))
        selectionPress.minimumPressDuration = 0.5
        selectionPress.allowableMovement = 10
        selectionPress.numberOfTouchesRequired = 1
        selectionPress.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        selectionPress.delegate = self
        selectionPress.require(toFail: startHandle.pan)
        selectionPress.require(toFail: endHandle.pan)
        for gesture in gestureRecognizers ?? [] where gesture is UIPanGestureRecognizer {
            gesture.require(toFail: selectionPress)
            gesture.require(toFail: startHandle.pan)
            gesture.require(toFail: endHandle.pan)
        }
        addGestureRecognizer(selectionPress)
        addInteraction(copyMenu)
        let render = core.onPostRender
        core.onPostRender = { [weak self] in
            render?()
            self?.validateSelection()
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    open override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        if recognizer === selectionPress { return surface != nil }
        if recognizer is UILongPressGestureRecognizer { return false }
        return super.gestureRecognizerShouldBegin(recognizer)
    }

    open override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01, bounds.contains(point) else { return nil }
        if selection != nil {
            // Short words have overlapping 44pt targets. The closest knob wins
            // so both endpoints remain independently reachable.
            let handles = [startHandle, endHandle].filter { !$0.isHidden && $0.frame.contains(point) }
            if let nearest = handles.min(by: { lhs, rhs in
                let left = lhs.convert(lhs.knob.center, to: self)
                let right = rhs.convert(rhs.knob.center, to: self)
                return hypot(point.x - left.x, point.y - left.y) < hypot(point.x - right.x, point.y - right.y)
            }) { return nearest }
        }
        return super.hitTest(point, with: event)
    }

    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Touches on the handles belong to their own recognizers, not the terminal.
        if let touch = touches.first, let view = touch.view,
           view.isDescendant(of: startHandle) || view.isDescendant(of: endHandle) { return }
        clearSelection()
        super.touchesBegan(touches, with: event)
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        highlight.frame = bounds
        if let grid = selectionGrid, grid != currentGrid() { clearSelection() }
        updateHandles()
    }

    open override func didMoveToWindow() {
        if window == nil { clearSelection() }
        super.didMoveToWindow()
    }

    private func currentGrid() -> TerminalSelectionGrid? {
        guard let metrics = surface?.size() else { return nil }
        return TerminalSelectionGrid(metrics: metrics, scale: resolvedDisplayScale(), origin: selectionGridOrigin)
    }

    @objc private func selectText(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            guard let grid = currentGrid(), let surface else { return }
            stopMomentumScrolling()
            softwareKeyboard.tapCandidateArmed = false
            selectionGrid = grid
            selection = surface.wordSelection(at: point)
                ?? TerminalViewportSelection(start: grid.cell(at: point), end: grid.cell(at: point))
            pressRange = selection
            refreshSelection()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .changed:
            guard let grid = selectionGrid, let initial = pressRange else { return }
            let cell = grid.cell(at: point)
            selection = TerminalViewportSelection(start: min(initial.start, cell), end: max(initial.end, cell))
            refreshSelection()
        case .ended:
            pressRange = nil
            presentCopyMenu(at: point)
        case .cancelled, .failed:
            pressRange = nil
        default: break
        }
    }

    @objc private func dragHandle(_ gesture: UIPanGestureRecognizer) {
        guard let grid = selectionGrid, var range = selection else { return }
        let isStart = gesture === startHandle.pan
        let touch = gesture.location(in: self)
        if gesture.state == .began {
            copyMenu.dismissMenu()
            handleTouch = touch
            // Use the cell's center for mapping, so grabbing a knob below/above
            // the text does not jump the selection to a different line.
            let rect = grid.rect(for: isStart ? range.start : range.end)
            handleAnchor = CGPoint(x: rect.midX, y: rect.midY)
        }
        if gesture.state == .began || gesture.state == .changed || gesture.state == .ended {
            let point = CGPoint(x: handleAnchor.x + touch.x - handleTouch.x,
                                y: handleAnchor.y + touch.y - handleTouch.y)
            let cell = grid.cell(at: point)
            if isStart { range.moveStart(to: cell) } else { range.moveEnd(to: cell) }
            selection = range
            refreshSelection()
        }
        if gesture.state == .ended || gesture.state == .cancelled {
            presentCopyMenu(at: touch)
        }
    }

    private func refreshSelection() {
        guard var range = selection else { return }
        if let start = surface?.characterSelection(at: range.start) { range.start = start.start }
        if let end = surface?.characterSelection(at: range.end) { range.end = end.end }
        selection = range
        selectedText = surface?.readText(in: range)
        updateHandles()
    }

    private func updateHandles() {
        guard let range = selection, let grid = selectionGrid else { return }
        highlight.rects = grid.rects(for: range)
        let start = grid.rect(for: range.start)
        let end = grid.rect(for: range.end)
        startHandle.place(at: CGPoint(x: start.minX, y: start.minY), lineHeight: start.height, in: bounds)
        endHandle.place(at: CGPoint(x: end.maxX, y: end.minY), lineHeight: end.height, in: bounds)
        startHandle.isHidden = false
        endHandle.isHidden = false
        bringSubviewToFront(highlight)
        bringSubviewToFront(startHandle)
        bringSubviewToFront(endHandle)
    }

    private func clearSelection() {
        selection = nil
        selectedText = nil
        selectionGrid = nil
        pressRange = nil
        highlight.rects = []
        startHandle.isHidden = true
        endHandle.isHidden = true
        copyMenu.dismissMenu()
    }

    private func validateSelection() {
        guard let selection else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastValidation > 0.2 else { return }
        lastValidation = now
        if selectionGrid != currentGrid() || surface?.readText(in: selection) != selectedText {
            clearSelection()
        }
    }

    private func presentCopyMenu(at point: CGPoint) {
        guard let selectedText, !selectedText.isEmpty else { return }
        copyMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
    }

    open override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(copy(_:)), selection != nil { return !(selectedText?.isEmpty ?? true) }
        return super.canPerformAction(action, withSender: sender)
    }

    @discardableResult
    open override func copySelectedTextToPasteboard() -> Bool {
        guard let selection else { return super.copySelectedTextToPasteboard() }
        // Never copy a different region if output changed while the menu was open.
        guard let text = surface?.readText(in: selection), text == selectedText else {
            clearSelection()
            return false
        }
        UIPasteboard.general.string = text
        return true
    }
}

@available(iOS 16.0, *)
extension TerminalSelectableView: @preconcurrency UIEditMenuInteractionDelegate {
    public func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                                    menuFor configuration: UIEditMenuConfiguration,
                                    suggestedActions: [UIMenuElement]) -> UIMenu? {
        UIMenu(children: [UIAction(title: NSLocalizedString("COPY", value: "Copy", comment: "Copy terminal text"),
                                  image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
            self?.copySelectedTextToPasteboard()
        }])
    }
}

private final class SelectionHighlightView: UIView {
    var rects: [CGRect] = [] { didSet { setNeedsDisplay() } }
    override func draw(_ rect: CGRect) {
        tintColor.withAlphaComponent(0.25).setFill()
        for rect in rects { UIRectFill(rect) }
    }
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isOpaque = false }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class SelectionHandle: UIView {
    let isStart: Bool
    let stem = UIView()
    let knob = UIView()
    let pan = UIPanGestureRecognizer()

    init(isStart: Bool) {
        self.isStart = isStart
        super.init(frame: .zero)
        accessibilityIdentifier = isStart ? "terminal.selectionStart" : "terminal.selectionEnd"
        addSubview(stem)
        addSubview(knob)
        addGestureRecognizer(pan)
        pan.maximumNumberOfTouches = 1
        knob.layer.cornerRadius = 5
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func tintColorDidChange() {
        super.tintColorDidChange()
        stem.backgroundColor = tintColor
        knob.backgroundColor = tintColor
    }
    func place(at point: CGPoint, lineHeight: CGFloat, in bounds: CGRect) {
        let width: CGFloat = 44
        let height = max(44, lineHeight + 20)
        let x = min(max(point.x - width / 2, bounds.minX), max(bounds.minX, bounds.maxX - width))
        let y = min(max(point.y - 10, bounds.minY), max(bounds.minY, bounds.maxY - height))
        frame = CGRect(x: x, y: y, width: width, height: height)
        let stemX = point.x - x
        let stemY = point.y - y
        stem.frame = CGRect(x: stemX - 1, y: stemY, width: 2, height: lineHeight)
        knob.frame = CGRect(x: min(max(stemX - 5, 0), width - 10),
                            y: min(max(isStart ? stemY - 10 : stemY + lineHeight, 0), height - 10),
                            width: 10, height: 10)
        stem.backgroundColor = tintColor
        knob.backgroundColor = tintColor
    }
}
#endif
