import AppKit

/// Status glyph at the inner end of a tray row: spinner, pulsing dot, or check.
private final class GlyphView: NSView {
    init(state: AgentState, tint: NSColor) {
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        wantsLayer = true
        let l = layer!
        switch state {
        case .working:
            let track = CAShapeLayer(), arc = CAShapeLayer()
            for s in [track, arc] {
                s.frame = bounds
                s.path = CGPath(ellipseIn: bounds.insetBy(dx: 1.5, dy: 1.5), transform: nil)
                s.fillColor = nil
                s.lineWidth = 2
                s.lineCap = .round
                l.addSublayer(s)
            }
            track.strokeColor = NSColor(white: 1, alpha: 0.13).cgColor
            arc.strokeColor = tint.cgColor
            arc.strokeEnd = 0.28
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi
            spin.duration = 1.1
            spin.repeatCount = .infinity
            arc.add(spin, forKey: "spin")
        case .question:
            let dot = CALayer()
            dot.frame = bounds.insetBy(dx: 4, dy: 4)
            dot.cornerRadius = 4
            dot.backgroundColor = NSColor.systemOrange.cgColor
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.3
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            dot.add(pulse, forKey: "pulse")
            l.addSublayer(dot)
        case .done:
            let img = NSImageView(image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil) ?? NSImage())
            img.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
            img.contentTintColor = .systemGreen
            img.frame = bounds
            addSubview(img)
        case .idle:
            let dot = CALayer()
            dot.frame = bounds.insetBy(dx: 5.5, dy: 5.5)
            dot.cornerRadius = 2.5
            dot.backgroundColor = NSColor(white: 1, alpha: 0.22).cgColor
            l.addSublayer(dot)
        }
    }
    required init?(coder: NSCoder) { nil }
}

/// Text half of an open tray, at notch height. Sprites stay in the island's layer tree
/// and slide out beside it; each agent on the side gets one segment.
final class TrayView: NSView {
    struct Row {
        let agent: AgentConfig
        let state: AgentState
        let session: Session?
        let usage: Usage?
        let states: [AgentState]
        let keys: [String]
        let selected: Int
    }

    /// Clickable session pips, in this view's coordinates.
    private(set) var pips: [(rect: CGRect, key: String)] = []

    static let segW: CGFloat = 270, inset: CGFloat = 8, iconW: CGFloat = 30, edge: CGFloat = 12

    /// Segment 0 sits next to the notch, later ones further out, matching the collapsed order.
    static func segment(_ i: Int, side: Side, in r: CGRect) -> CGRect {
        side == .left ? CGRect(x: r.maxX - inset - CGFloat(i + 1) * segW, y: r.minY, width: segW, height: r.height)
                      : CGRect(x: r.minX + inset + CGFloat(i) * segW, y: r.minY, width: segW, height: r.height)
    }

    init(frame: NSRect, side: Side, rows: [Row]) {
        super.init(frame: frame)
        let left = side == .left
        let h = frame.height
        for (i, r) in rows.enumerated() {
            var seg = Self.segment(i, side: side, in: frame)
            seg.origin.x -= frame.minX
            let textX0 = left ? seg.minX + Self.edge + Self.iconW + 10 : seg.minX + 30
            let textX1 = left ? seg.maxX - 30 : seg.maxX - Self.edge - Self.iconW - 10
            let tw = textX1 - textX0
            let align: NSTextAlignment = left ? .left : .right

            // Name line: name, session pips, usage — laid out outward-in from the text edge.
            let name = label(r.agent.displayName, 11.5, .semibold, .white)
            name.sizeToFit()
            var pieces: [NSView] = [name]
            if r.states.count > 1 {
                let n = min(r.states.count, 6)
                let box = NSView(frame: NSRect(x: 0, y: 0, width: CGFloat(n) * 9 - 3, height: 6))
                box.wantsLayer = true
                for i in 0..<n {
                    let d = CALayer()
                    d.frame = CGRect(x: CGFloat(left ? i : n - 1 - i) * 9, y: 0, width: 6, height: 6)
                    d.cornerRadius = 3
                    d.backgroundColor = IslandController.color(r.states[i], tint: r.agent.tint).cgColor
                    d.opacity = i == r.selected ? 1 : 0.55
                    if i == r.selected { d.borderWidth = 1.2; d.borderColor = NSColor(white: 1, alpha: 0.9).cgColor }
                    box.layer?.addSublayer(d)
                }
                box.identifier = NSUserInterfaceItemIdentifier("pips")
                pieces.append(box)
            }
            if let u = r.usage {
                let usage = label("5h \(Int(u.fiveHour.rounded()))%", 9.5, .medium,
                                  u.fiveHour >= 85 ? .systemOrange : NSColor(white: 1, alpha: 0.4), mono: true)
                usage.sizeToFit()
                pieces.append(usage)
            }
            var x = left ? textX0 : textX1
            let midY = h / 2 - 7.5
            for v in pieces {
                let w = min(v.frame.width, tw)
                if !left { x -= w }
                v.frame = NSRect(x: x, y: midY - v.frame.height / 2, width: w, height: v.frame.height)
                addSubview(v)
                if v.identifier?.rawValue == "pips" {
                    let n = min(r.states.count, 6)
                    for i in 0..<n {
                        let px = v.frame.minX + CGFloat(left ? i : n - 1 - i) * 9
                        pips.append((CGRect(x: px - 2, y: 0, width: 10, height: h), r.keys[i]))
                    }
                }
                x += left ? w + 7 : -7
            }

            let detail = label(detailText(r), 10.5, .regular, NSColor(white: 1, alpha: 0.55))
            detail.alignment = align
            detail.frame = NSRect(x: textX0, y: h / 2 + 0.5, width: tw, height: 14)
            addSubview(detail)

            let g = GlyphView(state: r.state, tint: r.agent.tint)
            g.frame.origin = CGPoint(x: left ? seg.maxX - 24 : seg.minX + 8, y: h / 2 - 8)
            addSubview(g)
        }
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override func hitTest(_ p: NSPoint) -> NSView? { nil }

    private func label(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, mono: Bool = false) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        t.textColor = color
        t.lineBreakMode = .byTruncatingTail
        return t
    }

    private func detailText(_ r: Row) -> String {
        guard let s = r.session else { return "" }
        var task = s.prompt ?? s.project
        if let t = s.title.map(Self.clean), !t.isEmpty, !Self.generic(t) { task = t }
        let what: String
        switch r.state {
        case .question: what = "Waiting for you"
        case .working: what = s.action ?? "Thinking…"
        case .done: what = "Finished " + Self.ago(s.updated)
        case .idle: what = "Idle"
        }
        let parts = [task, what]
        return parts.joined(separator: " · ")
    }

    /// Terminal titles lead with a spinner or status glyph.
    static func clean(_ t: String) -> String {
        String(t.drop { !$0.isLetter && !$0.isNumber }).trimmingCharacters(in: .whitespaces)
    }

    private static func generic(_ t: String) -> Bool {
        let l = t.lowercased()
        return l == "claude code" || l == "codex" || l.hasPrefix("~") || l.hasPrefix("/") || l.contains("@")
    }

    private static func ago(_ d: Date) -> String {
        let s = Int(-d.timeIntervalSinceNow)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }
}
