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

/// Text half of an open tray. Sprites stay in the island's layer tree and glide in beside it.
final class TrayView: NSView {
    struct Row {
        let agent: AgentConfig
        let state: AgentState
        let session: Session?
        let count: Int
        let usage: Usage?
    }

    static let rowH: CGFloat = 58, iconW: CGFloat = 46, edge: CGFloat = 14, top: CGFloat = 6

    init(frame: NSRect, side: Side, rows: [Row]) {
        super.init(frame: frame)
        let left = side == .left
        let textX0 = left ? Self.edge + Self.iconW + 12 : 44
        let textX1 = left ? frame.width - 44 : frame.width - Self.edge - Self.iconW - 12
        let tw = textX1 - textX0
        for (i, r) in rows.enumerated() {
            let y0 = Self.top + CGFloat(i) * Self.rowH
            let align: NSTextAlignment = left ? .left : .right

            var usageW: CGFloat = 0
            if let u = r.usage {
                let pct = label("5h \(Int(u.fiveHour.rounded()))%", 10, .medium, NSColor(white: 1, alpha: 0.45), mono: true)
                pct.sizeToFit()
                let barW: CGFloat = 34
                usageW = pct.frame.width + barW + 6
                let ux = left ? textX1 - usageW : textX0
                let track = CALayer(), fill = CALayer()
                track.frame = CGRect(x: 0, y: 0, width: barW, height: 3)
                track.cornerRadius = 1.5
                track.backgroundColor = NSColor(white: 1, alpha: 0.14).cgColor
                fill.frame = CGRect(x: 0, y: 0, width: barW * min(1, max(0.04, u.fiveHour / 100)), height: 3)
                fill.cornerRadius = 1.5
                fill.backgroundColor = (u.fiveHour >= 85 ? NSColor.systemOrange : r.agent.tint).cgColor
                let bar = NSView(frame: NSRect(x: left ? ux : ux + pct.frame.width + 6, y: y0 + 13, width: barW, height: 3))
                bar.wantsLayer = true
                bar.layer?.addSublayer(track)
                bar.layer?.addSublayer(fill)
                pct.frame.origin = CGPoint(x: left ? ux + barW + 6 : ux, y: y0 + 7)
                addSubview(bar)
                addSubview(pct)
            }

            let name = label(r.agent.displayName, 13, .semibold, .white)
            name.alignment = align
            name.frame = NSRect(x: left ? textX0 : textX0 + usageW + 8, y: y0 + 5, width: tw - usageW - 8, height: 17)
            addSubview(name)

            let task = label(taskText(r), 11.5, .regular, NSColor(white: 1, alpha: 0.66))
            task.alignment = align
            task.frame = NSRect(x: textX0, y: y0 + 23, width: tw, height: 15)
            addSubview(task)

            let act = label(actionText(r), 10.5, .regular, NSColor(white: 1, alpha: 0.4))
            act.alignment = align
            act.frame = NSRect(x: textX0, y: y0 + 39, width: tw, height: 14)
            addSubview(act)

            let g = GlyphView(state: r.state, tint: r.agent.tint)
            g.frame.origin = CGPoint(x: left ? frame.width - 30 : 14, y: y0 + Self.rowH / 2 - 8 - 3)
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

    private func taskText(_ r: Row) -> String {
        guard let s = r.session else { return "" }
        if let t = s.title.map(Self.clean), !t.isEmpty, !Self.generic(t) { return t }
        return s.prompt ?? s.project
    }

    private func actionText(_ r: Row) -> String {
        guard let s = r.session else { return "" }
        let what: String
        switch r.state {
        case .question: what = "Waiting for you"
        case .working: what = s.action ?? "Thinking…"
        case .done: what = "Finished " + Self.ago(s.updated)
        case .idle: what = "Idle"
        }
        var parts = [s.project, what]
        if r.count > 1 { parts.append("\(r.count) sessions") }
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
