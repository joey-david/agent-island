import AppKit

/// Status glyph at the inner end of a tray row: spinner, pulsing dot, check, pause, or hourglass.
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
        case .done, .interrupted, .limited:
            let symbol = state == .done ? "checkmark.circle.fill" : state == .limited ? "hourglass.circle.fill" : "pause.circle.fill"
            let img = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
            img.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
            img.contentTintColor = IslandController.color(state, tint: tint)
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
        /// Every session of the agent, in the same order as `states`.
        let sessions: [Session]
        let keys: [String]
        let selected: Int
        /// Picked with the arrow keys.
        let focused: Bool
        /// Switching between this agent's sessions (pip hover or arrows): name the session, not its activity.
        let switching: Bool
    }

    /// Clickable session pips, in this view's coordinates.
    private(set) var pips: [(rect: CGRect, key: String)] = []

    static let maxW: CGFloat = 270, inset: CGFloat = 8, iconW: CGFloat = 30, edge: CGFloat = 12
    /// Everything in a segment but its text: mascot and padding on one end, status glyph on the other.
    private static let chrome = edge + iconW + 10 + 30

    /// Just wide enough for the row's longer line, in 8pt steps so small text changes don't twitch it.
    /// With several sessions it fits the widest of them, title or activity, so switching between
    /// them never moves the pips.
    static func width(_ r: Row) -> CGFloat {
        var name = label(r.agent.displayName, 11.5, .semibold, .white).fittingSize.width
        if r.states.count > 1 { name += 7 + CGFloat(min(r.states.count, 6)) * 12 - 4 }
        if let u = r.usage { name += 7 + usageLabel(u).fittingSize.width }
        var lines = [detailText(r.session, r.state, switching: r.switching)]
        if r.sessions.count > 1 {
            for (s, st) in zip(r.sessions, r.states) { lines += [false, true].map { detailText(s, st, switching: $0) } }
        }
        let detail = lines.map { label($0, 10.5, .regular, .white).fittingSize.width }.max() ?? 0
        let w = chrome + max(name, detail, 40)
        return min(maxW, (w / 8).rounded(.up) * 8)
    }

    /// Segment 0 sits next to the notch, later ones further out, matching the collapsed order.
    static func segment(_ i: Int, side: Side, in r: CGRect, widths: [CGFloat]) -> CGRect {
        let before = widths.prefix(i).reduce(0, +), w = widths[i]
        return side == .left ? CGRect(x: r.maxX - inset - before - w, y: r.minY, width: w, height: r.height)
                             : CGRect(x: r.minX + inset + before, y: r.minY, width: w, height: r.height)
    }

    init(frame: NSRect, side: Side, rows: [Row]) {
        super.init(frame: frame)
        let left = side == .left
        let h = frame.height
        let widths = rows.map(Self.width)
        for (i, r) in rows.enumerated() {
            var seg = Self.segment(i, side: side, in: frame, widths: widths)
            seg.origin = CGPoint(x: seg.minX - frame.minX, y: 0)
            if r.focused {
                let hl = NSView(frame: seg.insetBy(dx: 2, dy: 3))
                hl.wantsLayer = true
                hl.layer?.cornerRadius = 9
                hl.layer?.cornerCurve = .continuous
                hl.layer?.backgroundColor = NSColor(white: 1, alpha: 0.09).cgColor
                addSubview(hl)
            }
            let textX0 = left ? seg.minX + Self.edge + Self.iconW + 10 : seg.minX + 30
            let textX1 = left ? seg.maxX - 30 : seg.maxX - Self.edge - Self.iconW - 10
            let tw = textX1 - textX0
            let align: NSTextAlignment = left ? .left : .right

            // Name line: name, session pips, usage — laid out outward-in from the text edge.
            let name = Self.label(r.agent.displayName, 11.5, .semibold, .white)
            name.sizeToFit()
            var pieces: [NSView] = [name]
            if r.states.count > 1 {
                let n = min(r.states.count, 6)
                let box = NSView(frame: NSRect(x: 0, y: 0, width: CGFloat(n) * 12 - 4, height: 8))
                box.wantsLayer = true
                for i in 0..<n {
                    let d = CALayer()
                    d.frame = CGRect(x: CGFloat(left ? i : n - 1 - i) * 12, y: 0, width: 8, height: 8)
                    d.cornerRadius = 4
                    d.backgroundColor = IslandController.color(r.states[i], tint: r.agent.tint).cgColor
                    d.opacity = i == r.selected ? 1 : 0.55
                    if i == r.selected { d.borderWidth = 1.2; d.borderColor = NSColor(white: 1, alpha: 0.9).cgColor }
                    box.layer?.addSublayer(d)
                }
                box.identifier = NSUserInterfaceItemIdentifier("pips")
                pieces.append(box)
            }
            if let u = r.usage {
                let usage = Self.usageLabel(u)
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
                        let px = v.frame.minX + CGFloat(left ? i : n - 1 - i) * 12
                        pips.append((CGRect(x: px - 2, y: 0, width: 12, height: h), r.keys[i]))
                    }
                }
                x += left ? w + 7 : -7
            }

            let detail = Self.label(Self.detailText(r.session, r.state, switching: r.switching), 10.5, .regular, NSColor(white: 1, alpha: 0.55))
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

    /// The window nearest its limit, so a spent week isn't hidden behind a fresh five hours.
    private static func usageLabel(_ u: Usage) -> NSTextField {
        let w = u.binding
        let color = w.used >= 100 ? .systemRed : w.used >= 85 ? .systemOrange : NSColor(white: 1, alpha: 0.4)
        return label("\(w.label) \(Int(w.used.rounded()))%", 9.5, .medium, color, mono: true)
    }

    private static func label(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, mono: Bool = false) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        t.textColor = color
        t.lineBreakMode = .byTruncatingTail
        return t
    }

    private static func detailText(_ session: Session?, _ state: AgentState, switching: Bool) -> String {
        guard let s = session else { return "" }
        if switching {
            // Codex titles its terminal "<task> | <directory>".
            if s.parent == nil, let t = s.title.map({ Self.clean($0).replacingOccurrences(of: " | " + s.project, with: "") }),
               !t.isEmpty, !Self.generic(t), t != s.project { return t }
            return s.prompt ?? s.project
        }
        switch state {
        case .question: return "Waiting for you"
        case .working: return s.action ?? "Thinking…"
        case .done, .idle: return s.state == .done ? "Finished " + Self.ago(s.updated) : "Idle"
        case .interrupted: return s.reason ?? "Interrupted " + Self.ago(s.updated)
        case .limited: return s.limitResets.map { "Out of usage until " + Self.when($0) } ?? "Out of usage"
        }
    }

    private static func when(_ d: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(Calendar.current.isDateInToday(d) ? "jmm" : d.timeIntervalSinceNow < 6 * 86400 ? "EEEjmm" : "dMMMjmm")
        return f.string(from: d)
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
