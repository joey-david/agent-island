import AppKit

/// A rounded, hover-lit click target that owns every click inside it.
final class HoverButton: NSView {
    var onClick: (() -> Void)?
    var normal: NSColor { didSet { layer?.backgroundColor = normal.cgColor } }
    private let hot: NSColor
    private var area: NSTrackingArea?

    init(normal: NSColor, hot: NSColor, radius: CGFloat = 10) {
        self.normal = normal
        self.hot = hot
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = normal.cgColor
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ p: NSPoint) -> NSView? { frame.contains(p) ? self : nil }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }
    override func mouseEntered(with e: NSEvent) { highlight(true) }
    override func mouseExited(with e: NSEvent) { highlight(false) }
    func highlight(_ on: Bool) { layer?.backgroundColor = (on ? hot : normal).cgColor }
    override func mouseDown(with e: NSEvent) { layer?.opacity = 0.7 }
    override func mouseUp(with e: NSEvent) {
        layer?.opacity = 1
        if bounds.contains(convert(e.locationInWindow, from: nil)) { onClick?() }
    }

    func fill(_ content: NSView, h: CGFloat = 10, v: CGFloat = 8) {
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: h),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -h),
            content.topAnchor.constraint(equalTo: topAnchor, constant: v),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -v),
        ])
    }
}

private final class StillView: NSView {
    init(_ image: CGImage?, pixelated: Bool, height: CGFloat, aspect: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = pixelated ? .nearest : .linear
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: height),
                                     widthAnchor.constraint(equalToConstant: (height * aspect).rounded())])
    }
    required init?(coder: NSCoder) { nil }
}

private func label(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor = .white,
                   mono: Bool = false, wrap: CGFloat? = nil) -> NSTextField {
    let t = wrap == nil ? NSTextField(labelWithString: s) : NSTextField(wrappingLabelWithString: s)
    t.font = mono ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
    t.textColor = color
    t.isSelectable = false
    t.translatesAutoresizingMaskIntoConstraints = false
    if let wrap {
        t.preferredMaxLayoutWidth = wrap
        t.widthAnchor.constraint(lessThanOrEqualToConstant: wrap).isActive = true
    } else {
        t.lineBreakMode = .byTruncatingTail
    }
    return t
}

private func row(_ views: [NSView], spacing: CGFloat = 6) -> NSStackView {
    let s = NSStackView(views: views)
    s.orientation = .horizontal
    s.alignment = .centerY
    s.spacing = spacing
    s.translatesAutoresizingMaskIntoConstraints = false
    return s
}

private func spacer() -> NSView {
    let v = NSView()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.setContentHuggingPriority(.init(1), for: .horizontal)
    v.setContentCompressionResistancePriority(.init(1), for: .horizontal)
    return v
}

/// The question panel dropped from the widened island: AskUserQuestion choices or a permission prompt.
/// Compact rows — keycap, label, dim description on one line — in the island's own black.
final class BubbleView: NSView, NSTextFieldDelegate {
    let pending: Pending
    var onAnswer: ((String) -> Void)?
    var onChat: (() -> Void)?
    var onResize: (() -> Void)?

    private let agent: AgentConfig
    private var index = 0
    private var answers: [String: String] = [:]
    private var picked = Set<Int>()
    private let stack = NSStackView()
    let width: CGFloat
    private let insetH: CGFloat = 14, insetTop: CGFloat = 8, insetBottom: CGFloat = 12
    private var inner: CGFloat { width - 2 * insetH }

    init(pending: Pending, agent: AgentConfig, sprite: Sprite, width: CGFloat = 380) {
        self.width = width
        self.pending = pending
        self.agent = agent
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insetH),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: insetTop),
            stack.widthAnchor.constraint(equalToConstant: inner),
        ])
        rebuild()
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    var preferredSize: CGSize {
        stack.layoutSubtreeIfNeeded()
        return CGSize(width: width, height: ceil(stack.fittingSize.height + insetTop + insetBottom))
    }

    private func add(_ v: NSView, full: Bool = true, after: CGFloat? = nil) {
        stack.addArrangedSubview(v)
        if full { v.widthAnchor.constraint(equalToConstant: inner).isActive = true }
        if let after { stack.setCustomSpacing(after, after: v) }
    }

    private var dim: NSColor { NSColor(white: 1, alpha: 0.42) }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch pending.kind {
        case .ask(let qs, _):
            let q = qs[index]
            var title: [NSView] = [label(q.text, 13, .semibold, wrap: inner - 70), spacer()]
            if qs.count > 1 { title.append(label("\(index + 1)/\(qs.count)", 10.5, .medium, dim, mono: true)) }
            if !q.header.isEmpty { title.append(chip(q.header)) }
            add(row(title), after: 8)
            for (i, o) in q.options.enumerated() { add(option(i, o, multi: q.multi)) }
            stack.setCustomSpacing(6, after: stack.arrangedSubviews.last!)
            add(otherField(), after: 8)
            var foot: [NSView] = [textButton("Open chat") { [weak self] in self?.onChat?() }, spacer()]
            if q.multi { foot.append(pill("Submit", accent: true) { [weak self] in self?.submitPicked() }) }
            add(row(foot))
        case .permission(let tool, let summary):
            let head = row([label("Allow \(tool)?", 13, .semibold), spacer(), chip("Permission")])
            add(head, after: 8)
            if !summary.isEmpty {
                let code = HoverButton(normal: NSColor(white: 1, alpha: 0.06), hot: NSColor(white: 1, alpha: 0.06), radius: 8)
                let t = label(String(summary.prefix(600)), 11, .regular, NSColor(white: 1, alpha: 0.8), mono: true, wrap: inner - 20)
                t.maximumNumberOfLines = 4
                code.fill(t, h: 10, v: 7)
                add(code, after: 10)
            }
            add(row([textButton("Open chat") { [weak self] in self?.onChat?() }, spacer(),
                     pill("Deny", accent: false) { [weak self] in self.map { $0.onAnswer?($0.pending.output(allow: false)) } },
                     pill("Allow", accent: true) { [weak self] in self.map { $0.onAnswer?($0.pending.output(allow: true)) } }], spacing: 6))
        }
    }

    private func chip(_ text: String) -> NSView {
        let c = HoverButton(normal: agent.tint.withAlphaComponent(0.16), hot: agent.tint.withAlphaComponent(0.16), radius: 5)
        let t = label(text.uppercased(), 9, .bold, agent.tint.blended(withFraction: 0.35, of: .white) ?? agent.tint)
        c.fill(t, h: 6, v: 2)
        c.widthAnchor.constraint(equalTo: t.widthAnchor, constant: 12).isActive = true
        return c
    }

    private func option(_ i: Int, _ o: (label: String, detail: String), multi: Bool) -> NSView {
        let on = picked.contains(i)
        let b = HoverButton(normal: on ? agent.tint.withAlphaComponent(0.2) : NSColor(white: 1, alpha: 0.055),
                            hot: agent.tint.withAlphaComponent(on ? 0.26 : 0.16), radius: 8)
        let key = NSView()
        key.wantsLayer = true
        key.layer?.cornerRadius = 4
        key.layer?.backgroundColor = (on ? agent.tint : NSColor(white: 1, alpha: 0.1)).cgColor
        key.translatesAutoresizingMaskIntoConstraints = false
        let k = label(multi ? (on ? "✓" : "") : "\(i + 1)", 9.5, .bold, on ? .black : NSColor(white: 1, alpha: 0.65), mono: true)
        k.alignment = .center
        key.addSubview(k)
        NSLayoutConstraint.activate([key.widthAnchor.constraint(equalToConstant: 16), key.heightAnchor.constraint(equalToConstant: 16),
                                     k.centerXAnchor.constraint(equalTo: key.centerXAnchor), k.centerYAnchor.constraint(equalTo: key.centerYAnchor)])
        let title = label(o.label, 12.5, .medium)
        title.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        var parts: [NSView] = [key, title]
        if !o.detail.isEmpty {
            let d = label(o.detail, 11, .regular, dim)
            d.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            parts.append(d)
        }
        parts.append(spacer())
        b.fill(row(parts, spacing: 8), h: 8, v: 6)
        b.onClick = { [weak self] in
            guard let self else { return }
            if multi {
                if self.picked.contains(i) { self.picked.remove(i) } else { self.picked.insert(i) }
                self.rebuild()
            } else {
                self.answer(o.label)
            }
        }
        return b
    }

    private func otherField() -> NSView {
        let box = HoverButton(normal: NSColor(white: 1, alpha: 0.03), hot: NSColor(white: 1, alpha: 0.06), radius: 8)
        box.wantsLayer = true
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
        let f = NSTextField()
        f.placeholderAttributedString = NSAttributedString(string: "Something else…", attributes: [
            .foregroundColor: NSColor(white: 1, alpha: 0.3), .font: NSFont.systemFont(ofSize: 12)])
        f.font = .systemFont(ofSize: 12)
        f.textColor = .white
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.delegate = self
        f.translatesAutoresizingMaskIntoConstraints = false
        let ret = label("↩", 11, .medium, NSColor(white: 1, alpha: 0.25))
        box.addSubview(f)
        box.addSubview(ret)
        NSLayoutConstraint.activate([f.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
                                     f.trailingAnchor.constraint(equalTo: ret.leadingAnchor, constant: -6),
                                     ret.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
                                     ret.centerYAnchor.constraint(equalTo: box.centerYAnchor),
                                     f.topAnchor.constraint(equalTo: box.topAnchor, constant: 5),
                                     f.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -5)])
        box.onClick = { [weak f] in f?.window?.makeKey(); f?.window?.makeFirstResponder(f) }
        return box
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        guard sel == #selector(NSResponder.insertNewline(_:)) else { return false }
        let text = control.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { answer(text) }
        return true
    }

    private func textButton(_ title: String, _ action: @escaping () -> Void) -> NSView {
        let b = HoverButton(normal: .clear, hot: NSColor(white: 1, alpha: 0.08), radius: 6)
        let icon = NSImageView(image: NSImage(systemSymbolName: "arrow.up.forward", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = dim
        icon.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
        b.fill(row([label(title, 11, .medium, dim), icon], spacing: 3), h: 6, v: 3)
        b.onClick = action
        return b
    }

    private func pill(_ title: String, accent: Bool, _ action: @escaping () -> Void) -> NSView {
        let b = accent ? HoverButton(normal: agent.tint.withAlphaComponent(0.9), hot: agent.tint, radius: 7)
                       : HoverButton(normal: NSColor(white: 1, alpha: 0.1), hot: NSColor(white: 1, alpha: 0.17), radius: 7)
        b.fill(label(title, 12, .semibold, accent ? .black : .white), h: 13, v: 4)
        b.onClick = action
        return b
    }

    private func submitPicked() {
        guard case .ask(let qs, _) = pending.kind, !picked.isEmpty else { return }
        let opts = qs[index].options
        answer(picked.sorted().map { opts[$0].label }.joined(separator: ", "))
    }

    private func answer(_ text: String) {
        guard case .ask(let qs, _) = pending.kind else { return }
        answers[qs[index].text] = text
        picked = []
        index += 1
        if index >= qs.count {
            onAnswer?(pending.output(answers: answers))
        } else {
            rebuild()
            onResize?()
        }
    }
}
