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
    override func mouseEntered(with e: NSEvent) { layer?.backgroundColor = hot.cgColor }
    override func mouseExited(with e: NSEvent) { layer?.backgroundColor = normal.cgColor }
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

/// The question panel hanging from the island: AskUserQuestion choices or a permission prompt.
final class BubbleView: NSView, NSTextFieldDelegate {
    let pending: Pending
    var onAnswer: ((String) -> Void)?
    var onChat: (() -> Void)?
    var onResize: (() -> Void)?

    private let agent: AgentConfig
    private let sprite: Sprite
    private var index = 0
    private var answers: [String: String] = [:]
    private var picked = Set<Int>()
    private let stack = NSStackView()
    static let width: CGFloat = 400
    private let insetH: CGFloat = 18, insetTop: CGFloat = 12, insetBottom: CGFloat = 16
    private var inner: CGFloat { Self.width - 2 * insetH }

    init(pending: Pending, agent: AgentConfig, sprite: Sprite) {
        self.pending = pending
        self.agent = agent
        self.sprite = sprite
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 100))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
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
        return CGSize(width: Self.width, height: ceil(stack.fittingSize.height + insetTop + insetBottom))
    }

    private func add(_ v: NSView, full: Bool = false, after: CGFloat? = nil) {
        stack.addArrangedSubview(v)
        if full { v.widthAnchor.constraint(equalToConstant: inner).isActive = true }
        if let after { stack.setCustomSpacing(after, after: v) }
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch pending.kind {
        case .ask(let qs, _):
            let q = qs[index]
            add(header(chip: q.header, step: qs.count > 1 ? "\(index + 1)/\(qs.count)" : nil), full: true, after: 10)
            add(label(q.text, 14, .semibold, wrap: inner), after: 10)
            for (i, o) in q.options.enumerated() { add(option(i, o, multi: q.multi), full: true) }
            add(otherField(), full: true, after: 10)
            let chat = textButton("Open chat") { [weak self] in self?.onChat?() }
            if q.multi {
                add(row([chat, spacer(), accentButton("Submit") { [weak self] in self?.submitPicked() }]), full: true)
            } else {
                add(row([chat, spacer()]), full: true)
            }
        case .permission(let tool, let summary):
            add(header(chip: "Permission", step: nil), full: true, after: 10)
            add(label("Allow \(tool)?", 14, .semibold, wrap: inner), after: 8)
            if !summary.isEmpty {
                let code = HoverButton(normal: NSColor(white: 1, alpha: 0.06), hot: NSColor(white: 1, alpha: 0.06), radius: 8)
                let t = label(String(summary.prefix(600)), 11, .regular, NSColor(white: 1, alpha: 0.82), mono: true, wrap: inner - 20)
                t.maximumNumberOfLines = 6
                code.fill(t)
                add(code, full: true, after: 12)
            }
            let deny = HoverButton(normal: NSColor(white: 1, alpha: 0.1), hot: NSColor(white: 1, alpha: 0.18), radius: 8)
            deny.fill(label("Deny", 13, .medium), h: 16, v: 6)
            deny.onClick = { [weak self] in self.map { $0.onAnswer?($0.pending.output(allow: false)) } }
            let allow = accentButton("Allow") { [weak self] in self.map { $0.onAnswer?($0.pending.output(allow: true)) } }
            add(row([textButton("Open chat") { [weak self] in self?.onChat?() }, spacer(), deny, allow], spacing: 8), full: true)
        }
    }

    private func header(chip: String, step: String?) -> NSView {
        var views: [NSView] = [StillView(sprite.still(sprite.anims[.question]?.first?.frame ?? 0), pixelated: sprite.pixelated,
                                         height: 16, aspect: sprite.aspect),
                               label(agent.displayName, 11, .semibold, agent.tint),
                               label(pending.session.project, 11, .regular, NSColor(white: 1, alpha: 0.45)),
                               spacer()]
        if let step { views.append(label(step, 11, .medium, NSColor(white: 1, alpha: 0.45))) }
        if !chip.isEmpty {
            let c = HoverButton(normal: NSColor(white: 1, alpha: 0.1), hot: NSColor(white: 1, alpha: 0.1), radius: 6)
            c.fill(label(chip.uppercased(), 9, .bold, NSColor(white: 1, alpha: 0.7)), h: 6, v: 2)
            c.setContentHuggingPriority(.required, for: .horizontal)
            (c.subviews.first as? NSTextField)?.setContentHuggingPriority(.required, for: .horizontal)
            views.append(c)
        }
        return row(views)
    }

    private func option(_ i: Int, _ o: (label: String, detail: String), multi: Bool) -> NSView {
        let on = picked.contains(i)
        let b = HoverButton(normal: NSColor(white: 1, alpha: on ? 0.16 : 0.07), hot: NSColor(white: 1, alpha: 0.15))
        let key = HoverButton(normal: on ? agent.tint.withAlphaComponent(0.9) : NSColor(white: 1, alpha: 0.12),
                              hot: on ? agent.tint : NSColor(white: 1, alpha: 0.12), radius: 5)
        let keyText = label(multi ? (on ? "✓" : "") : "\(i + 1)", 10, .semibold, on ? .black : NSColor(white: 1, alpha: 0.7), mono: true)
        keyText.alignment = .center
        key.addSubview(keyText)
        NSLayoutConstraint.activate([key.widthAnchor.constraint(equalToConstant: 18), key.heightAnchor.constraint(equalToConstant: 18),
                                     keyText.centerXAnchor.constraint(equalTo: key.centerXAnchor),
                                     keyText.centerYAnchor.constraint(equalTo: key.centerYAnchor)])
        let text = NSStackView(views: [label(o.label, 13, .medium, wrap: inner - 50)])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        if !o.detail.isEmpty { text.addArrangedSubview(label(o.detail, 11, .regular, NSColor(white: 1, alpha: 0.5), wrap: inner - 50)) }
        let content = row([key, text], spacing: 10)
        content.alignment = .top
        b.fill(content)
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
        let box = HoverButton(normal: NSColor(white: 1, alpha: 0.05), hot: NSColor(white: 1, alpha: 0.08))
        let f = NSTextField()
        f.placeholderAttributedString = NSAttributedString(string: "Something else…", attributes: [
            .foregroundColor: NSColor(white: 1, alpha: 0.35), .font: NSFont.systemFont(ofSize: 13)])
        f.font = .systemFont(ofSize: 13)
        f.textColor = .white
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.delegate = self
        f.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(f)
        NSLayoutConstraint.activate([f.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
                                     f.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
                                     f.topAnchor.constraint(equalTo: box.topAnchor, constant: 7),
                                     f.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -7)])
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
        let b = HoverButton(normal: .clear, hot: NSColor(white: 1, alpha: 0.08), radius: 7)
        let icon = NSImageView(image: NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = NSColor(white: 1, alpha: 0.5)
        icon.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        b.fill(row([icon, label(title, 11, .medium, NSColor(white: 1, alpha: 0.5))], spacing: 4), h: 6, v: 4)
        b.onClick = action
        return b
    }

    private func accentButton(_ title: String, _ action: @escaping () -> Void) -> NSView {
        let b = HoverButton(normal: agent.tint.withAlphaComponent(0.88), hot: agent.tint, radius: 8)
        b.fill(label(title, 13, .semibold, .black), h: 16, v: 6)
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
