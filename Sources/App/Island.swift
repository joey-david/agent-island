import AppKit
import QuartzCore

final class IslandWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ r: NSRect, to s: NSScreen?) -> NSRect { r }
}

/// Hosts the hand-built layer tree; never takes mouse events itself.
private final class LayerHost: NSView {
    override func hitTest(_ p: NSPoint) -> NSView? { nil }
}

final class IslandView: NSView {
    weak var controller: IslandController?
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { controller?.click(convert(e.locationInWindow, from: nil)) }
    override func rightMouseDown(with e: NSEvent) { controller?.showMenu(e, in: self) }
    override func mouseEntered(with e: NSEvent) { controller?.pointerMoved() }
    override func mouseExited(with e: NSEvent) { controller?.pointerMoved() }
}

private final class Slot {
    let id: String
    let layer = CALayer()
    let dot = CALayer()
    var sprite: Sprite
    var anim: Anim?
    var dotState: AgentState?
    var leaving = false
    init(id: String, sprite: Sprite) { self.id = id; self.sprite = sprite }
}

final class IslandController: NSObject {
    private let window = IslandWindow()
    private let view = IslandView()
    private let host = LayerHost()
    private let root = CALayer()
    private let bar = CAShapeLayer(), panel = CAShapeLayer()
    private let trays: [Side: CAShapeLayer] = [.left: CAShapeLayer(), .right: CAShapeLayer()]
    private let mask = CALayer()
    private let barMask = CAShapeLayer()
    private let trayMasks: [Side: CAShapeLayer] = [.left: CAShapeLayer(), .right: CAShapeLayer()]
    private let slotLayer = CALayer()
    private var slots: [String: Slot] = [:]
    private var hits: [String: CGRect] = [:]
    private var wings: [Side: CGRect] = [:]
    private var trayRects: [Side: CGRect] = [:]
    private var notch = CGRect.zero
    private let height: CGFloat = 520
    private var visible = false
    private var hideToken = 0
    private var bubble: BubbleView?
    private var openSide: Side?
    private var tray: TrayView?
    private var trayKey = ""
    private var closeWork: DispatchWorkItem?
    private let store: SessionStore
    private let config: ConfigStore
    var menu: (() -> NSMenu)?

    private let pad: CGFloat = 12, gap: CGFloat = 10, trayW: CGFloat = 330
    private var bodyH: CGFloat { (notch.height * 0.56).rounded() }
    private let trayBodyH: CGFloat = 27
    private var top: CGFloat { height }

    init(store: SessionStore, config: ConfigStore) {
        self.store = store
        self.config = config
        super.init()
        window.contentView = view
        view.controller = self
        view.wantsLayer = true
        host.layer = root
        host.wantsLayer = true
        host.autoresizingMask = [.width, .height]
        view.addSubview(host)
        for s in [bar, panel, barMask] + Array(trays.values) + Array(trayMasks.values) { s.fillColor = NSColor.black.cgColor }
        root.addSublayer(panel)
        for s in trays.values { root.addSublayer(s) }
        root.addSublayer(bar)
        root.addSublayer(slotLayer)
        mask.addSublayer(barMask)
        for s in trayMasks.values { mask.addSublayer(s) }
        slotLayer.mask = mask
        layoutScreen()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.layoutScreen()
            self?.render(animated: false)
        }
    }

    // MARK: geometry

    private func layoutScreen() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let f = screen.frame
        let inset = screen.safeAreaInsets.top
        let nh = inset > 0 ? inset : max(24, f.maxY - screen.visibleFrame.maxY)
        var nx = f.width / 2 - 90, nw: CGFloat = 180
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            let origin = l.minX >= f.minX - 1 ? f.minX : 0
            nx = l.maxX - origin
            nw = r.minX - l.maxX
        }
        window.setFrame(NSRect(x: f.minX, y: f.maxY - height, width: f.width, height: height), display: false)
        host.frame = view.bounds
        for l in [root, slotLayer, mask] { l.frame = view.bounds }
        for l in [root, bar, barMask, panel, slotLayer] + Array(trays.values) + Array(trayMasks.values) {
            l.contentsScale = screen.backingScaleFactor
        }
        notch = CGRect(x: nx, y: height - nh, width: nw, height: nh)
        for s in slots.values { s.layer.removeFromSuperlayer() }
        slots.removeAll()
        collapse()
    }

    private func shape(_ minX: CGFloat, _ maxX: CGFloat, _ bottom: CGFloat, _ R: CGFloat) -> CGPath {
        let ear: CGFloat = 6
        let p = CGMutablePath()
        p.move(to: CGPoint(x: minX - ear, y: top))
        p.addQuadCurve(to: CGPoint(x: minX, y: top - ear), control: CGPoint(x: minX, y: top))
        p.addLine(to: CGPoint(x: minX, y: bottom + R))
        p.addCurve(to: CGPoint(x: minX + R, y: bottom), control1: CGPoint(x: minX, y: bottom + R * 0.45), control2: CGPoint(x: minX + R * 0.45, y: bottom))
        p.addLine(to: CGPoint(x: maxX - R, y: bottom))
        p.addCurve(to: CGPoint(x: maxX, y: bottom + R), control1: CGPoint(x: maxX - R * 0.45, y: bottom), control2: CGPoint(x: maxX, y: bottom + R * 0.45))
        p.addLine(to: CGPoint(x: maxX, y: top - ear))
        p.addQuadCurve(to: CGPoint(x: maxX + ear, y: top), control: CGPoint(x: maxX, y: top))
        p.closeSubpath()
        return p
    }

    private var barRadius: CGFloat { min(12, notch.height / 2 - 2) }
    private var notchPath: CGPath { shape(notch.minX, notch.maxX, notch.minY, barRadius) }

    private func collapse() {
        for l in [bar, barMask, panel] + Array(trays.values) + Array(trayMasks.values) { set(l, notchPath, animated: false) }
    }

    // MARK: render

    func reload() {
        for s in slots.values { s.layer.removeFromSuperlayer() }
        slots.removeAll()
        trayKey = ""
        render(animated: false)
    }

    func render(animated: Bool = true) {
        var sides: [Side: [(AgentConfig, AgentSummary)]] = [.left: [], .right: []]
        for a in config.config.agents where a.placement != .hidden {
            if let s = store.summary(a.id) { sides[a.placement]!.append((a, s)) }
        }
        let pending = store.pending.first
        let show = !sides[.left]!.isEmpty || !sides[.right]!.isEmpty || pending != nil
        if show && !visible {
            visible = true
            collapse()
            window.orderFrontRegardless()
        }
        if pending != nil || (openSide.map { sides[$0]!.isEmpty } ?? false) { openSide = nil }

        // Collapsed wings: bodies sit in a row, popping out from under the notch.
        var targets: [String: (center: CGPoint, scale: CGFloat)] = [:]
        hits = [:]
        let cy = notch.midY
        var edges: [Side: CGFloat] = [:]
        for side in [Side.left, .right] {
            let dir: CGFloat = side == .left ? -1 : 1
            var x = side == .left ? notch.minX - pad : notch.maxX + pad
            for (a, _) in sides[side]! {
                let sp = SpriteLibrary.sprite(for: a)
                let w = (bodyH * sp.weight * sp.bodyAspect).rounded()
                let cx = x + dir * w / 2
                targets[a.id] = (CGPoint(x: cx, y: cy), 1)
                hits[a.id] = CGRect(x: cx - w / 2 - gap / 2, y: notch.minY, width: w + gap, height: notch.height)
                x += dir * (w + gap)
            }
            edges[side] = sides[side]!.isEmpty ? (side == .left ? notch.minX : notch.maxX) : x - dir * gap + dir * pad
        }
        let minX = edges[.left]!, maxX = edges[.right]!
        wings = [.left: CGRect(x: minX, y: notch.minY, width: notch.minX - minX, height: notch.height),
                 .right: CGRect(x: notch.maxX, y: notch.minY, width: maxX - notch.maxX, height: notch.height)]
        let barPath = shape(minX, maxX, notch.minY, barRadius)
        set(bar, barPath, animated: animated)
        set(barMask, barPath, animated: animated)

        // The hovered side opens into a tray; its mascots glide down into their rows.
        trayRects = [:]
        for side in [Side.left, .right] {
            let rows = sides[side]!
            let path: CGPath
            if side == openSide {
                let w = max(trayW, wings[side]!.width)
                let h = TrayView.top * 2 + CGFloat(rows.count) * TrayView.rowH
                let r = side == .left ? CGRect(x: notch.minX - w, y: top - h, width: w, height: h)
                                      : CGRect(x: notch.maxX, y: top - h, width: w, height: h)
                trayRects[side] = r
                path = side == .left ? shape(r.minX, notch.maxX, r.minY, 22) : shape(notch.minX, r.maxX, r.minY, 22)
                for (i, (a, _)) in rows.enumerated() {
                    let rowTop = top - TrayView.top - CGFloat(i) * TrayView.rowH
                    let ix = side == .left ? r.minX + TrayView.edge + TrayView.iconW / 2 : r.maxX - TrayView.edge - TrayView.iconW / 2
                    targets[a.id] = (CGPoint(x: ix, y: rowTop - TrayView.rowH / 2 - 3), trayBodyH / bodyH)
                    hits[a.id] = CGRect(x: r.minX, y: rowTop - TrayView.rowH, width: r.width, height: TrayView.rowH)
                }
            } else {
                path = side == .left ? shape(minX, notch.maxX, notch.minY, barRadius) : shape(notch.minX, maxX, notch.minY, barRadius)
            }
            set(trays[side]!, path, animated: animated)
            set(trayMasks[side]!, path, animated: animated)
        }
        updateTrayView(sides)

        // The question panel drops out of the island.
        if let pending {
            if bubble?.pending !== pending { presentBubble(pending) }
            let size = bubble!.preferredSize
            let w = max(size.width, maxX - minX)
            bubble!.frame = CGRect(x: (notch.midX - size.width / 2).rounded(), y: notch.minY - size.height, width: size.width, height: size.height)
            set(panel, shape(notch.midX - w / 2, notch.midX + w / 2, notch.minY - size.height, 22), animated: animated)
        } else {
            dismissBubble()
            set(panel, notchPath, animated: animated)
        }

        var live = Set<String>()
        for side in [Side.left, .right] {
            for (a, summary) in sides[side]! {
                live.insert(a.id)
                let t = targets[a.id]!
                let sprite = SpriteLibrary.sprite(for: a)
                let slot: Slot
                if let s = slots[a.id], !s.leaving {
                    slot = s
                    if slot.sprite !== sprite { slot.sprite = sprite; dress(slot); slot.anim = nil }
                } else {
                    slots[a.id]?.layer.removeFromSuperlayer()
                    slot = Slot(id: a.id, sprite: sprite)
                    dress(slot)
                    slot.layer.position = behindNotch(sprite, left: side == .left)
                    slotLayer.addSublayer(slot.layer)
                    slots[a.id] = slot
                }
                move(slot.layer, to: t.center, animated: animated)
                scale(slot.layer, to: t.scale, animated: animated)
                apply(slot, summary)
            }
        }
        for (id, slot) in slots where !live.contains(id) && !slot.leaving {
            slot.leaving = true
            move(slot.layer, to: behindNotch(slot.sprite, left: slot.layer.position.x < notch.midX), animated: animated)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, let s = self.slots[id], s === slot, s.leaving else { return }
                s.layer.removeFromSuperlayer()
                self.slots.removeValue(forKey: id)
            }
        }
        trackPointer()

        hideToken += 1
        if !show && visible {
            let token = hideToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self, token == self.hideToken else { return }
                self.visible = false
                self.window.orderOut(nil)
            }
        }
    }

    private func behindNotch(_ s: Sprite, left: Bool) -> CGPoint {
        let w = bodyH * s.weight * s.bodyAspect
        return CGPoint(x: left ? notch.minX + w / 2 + 4 : notch.maxX - w / 2 - 4, y: notch.midY)
    }

    /// Sizes the layer so the resting body is `bodyH` tall, anchored on the body's centre.
    private func dress(_ slot: Slot) {
        let l = slot.layer, s = slot.sprite
        let h = bodyH * s.weight / s.body.height, w = h * s.aspect
        l.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        l.anchorPoint = CGPoint(x: s.body.midX, y: 1 - s.body.midY)
        l.contents = s.image
        l.contentsGravity = .resize
        l.contentsRect = s.rect(s.anims[.idle]?.first?.frame ?? 0)
        l.magnificationFilter = s.pixelated ? .nearest : .linear
        l.minificationFilter = s.pixelated ? .nearest : .trilinear
        l.contentsScale = window.backingScaleFactor
        slot.dot.bounds = CGRect(x: 0, y: 0, width: 5, height: 5)
        slot.dot.cornerRadius = 2.5
        slot.dot.opacity = 0
        slot.dot.position = CGPoint(x: s.body.maxX * w + 3, y: (1 - s.body.maxY) * h + 1)
        if slot.dot.superlayer == nil { l.addSublayer(slot.dot) }
    }

    private func apply(_ slot: Slot, _ summary: AgentSummary) {
        let anim: Anim
        switch summary.state {
        case .question: anim = .question
        case .working: anim = .working
        case .done: anim = .done
        case .idle: anim = .idle
        }
        if slot.anim != anim {
            slot.anim = anim
            play(slot)
        }
        guard slot.dotState != summary.state else { return }
        slot.dotState = summary.state
        slot.dot.removeAllAnimations()
        switch summary.state {
        case .question:
            slot.dot.backgroundColor = NSColor.systemOrange.cgColor
            slot.dot.opacity = 1
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.25
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 24)
            slot.dot.add(pulse, forKey: "pulse")
        case .done:
            slot.dot.backgroundColor = NSColor.systemGreen.cgColor
            slot.dot.opacity = 1
        default:
            slot.dot.opacity = 0
        }
    }

    private func play(_ slot: Slot) {
        let l = slot.layer, s = slot.sprite
        l.removeAnimation(forKey: "frames")
        l.removeAnimation(forKey: "once")
        guard let anim = slot.anim else { return }
        if anim == .done {
            l.add(track(s, .idle, repeats: .infinity), forKey: "frames")
            l.add(track(s, .done, repeats: 2), forKey: "once")
        } else {
            l.add(track(s, anim, repeats: .infinity), forKey: "frames")
        }
    }

    private func track(_ s: Sprite, _ a: Anim, repeats: Float) -> CAKeyframeAnimation {
        let frames = s.anims[a] ?? s.anims[.idle] ?? [(0, 1000)]
        let total = frames.reduce(0) { $0 + $1.ms }
        let k = CAKeyframeAnimation(keyPath: "contentsRect")
        k.values = frames.map { NSValue(rect: s.rect($0.frame)) }
        var t = 0.0, times: [NSNumber] = []
        for f in frames { times.append(NSNumber(value: t / total)); t += f.ms }
        times.append(1)
        k.keyTimes = times
        k.calculationMode = .discrete
        k.duration = total / 1000 * s.tempo
        k.repeatCount = repeats
        k.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 30, preferred: 15)
        return k
    }

    // MARK: tray

    private func updateTrayView(_ sides: [Side: [(AgentConfig, AgentSummary)]]) {
        guard let side = openSide, let r = trayRects[side] else {
            trayKey = ""
            if let t = tray {
                tray = nil
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.08; t.animator().alphaValue = 0 }, completionHandler: { t.removeFromSuperview() })
            }
            return
        }
        let rows = sides[side]!.map { a, sum -> TrayView.Row in
            let ss = store.sessions(of: a.id)
            return TrayView.Row(agent: a, state: sum.state, session: ss.first, count: ss.count, usage: Usage.read(a.id))
        }
        // Rebuild only when something visible changed.
        let key = "\(side)|\(r)|" + rows.map {
            "\($0.agent.id)\($0.state)\($0.count)\($0.session?.action ?? "")\($0.session?.title ?? "")\($0.session?.prompt ?? "")\(Int($0.usage?.fiveHour ?? -1))"
        }.joined(separator: "|")
        guard key != trayKey else { return }
        let fresh = tray == nil || !trayKey.hasPrefix("\(side)|")
        trayKey = key
        tray?.removeFromSuperview()
        let t = TrayView(frame: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height), side: side, rows: rows)
        view.addSubview(t)
        tray = t
        if fresh {
            t.alphaValue = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                NSAnimationContext.runAnimationGroup { $0.duration = 0.22; t.animator().alphaValue = 1 }
            }
        }
    }

    private func refreshTitles() {
        Focus.titles { [weak self] titles in
            guard let self, !titles.isEmpty else { return }
            for s in self.store.sessions.values where s.inGhostty {
                if s.terminalID == nil {
                    // Not seen being typed into yet: adopt the only terminal sitting in its directory.
                    let here = titles.filter { Focus.same($0.cwd, s.cwd) }
                    if here.count == 1 { s.terminalID = here[0].id }
                }
                if let id = s.terminalID, let t = titles.first(where: { $0.id == id }) { s.title = t.name }
            }
            if self.openSide != nil { self.render() }
        }
    }

    // MARK: animation helpers

    private func spring(_ l: CALayer, _ key: String, from: Any, to: Any) {
        let a = CASpringAnimation(keyPath: key)
        a.fromValue = from
        a.toValue = to
        a.mass = 1
        a.stiffness = 240
        a.damping = 22
        a.duration = a.settlingDuration
        l.add(a, forKey: key)
    }

    private func set(_ l: CAShapeLayer, _ p: CGPath, animated: Bool) {
        let from = l.presentation()?.path ?? l.path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.path = p
        CATransaction.commit()
        if animated, let from, from != p { spring(l, "path", from: from, to: p) } else if !animated { l.removeAnimation(forKey: "path") }
    }

    private func move(_ l: CALayer, to pos: CGPoint, animated: Bool) {
        let from = l.presentation()?.position ?? l.position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.position = pos
        CATransaction.commit()
        if animated && from != pos { spring(l, "position", from: NSValue(point: from), to: NSValue(point: pos)) }
    }

    private func scale(_ l: CALayer, to s: CGFloat, animated: Bool) {
        let from = (l.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat) ?? (l.value(forKeyPath: "transform.scale") as? CGFloat) ?? 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.setValue(s, forKeyPath: "transform.scale")
        CATransaction.commit()
        if animated && abs(from - s) > 0.001 { spring(l, "transform.scale", from: from, to: s) }
    }

    // MARK: bubble

    private func presentBubble(_ p: Pending) {
        bubble?.removeFromSuperview()
        let agent = config.agent(p.session.agent) ?? AgentConfig(id: p.session.agent)
        let b = BubbleView(pending: p, agent: agent, sprite: SpriteLibrary.sprite(for: agent))
        b.onAnswer = { [weak self] out in self?.store.answer(p, output: out) }
        b.onChat = { [weak self] in self?.openChat(p.session) }
        b.onResize = { [weak self] in self?.render() }
        b.alphaValue = 0
        view.addSubview(b)
        bubble = b
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; b.animator().alphaValue = 1 }
        }
    }

    private func dismissBubble() {
        guard let b = bubble else { return }
        bubble = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.1; b.animator().alphaValue = 0 }, completionHandler: { b.removeFromSuperview() })
    }

    // MARK: input

    private var pointer: CGPoint { view.convert(window.mouseLocationOutsideOfEventStream, from: nil) }

    private func trackPointer() {
        for a in view.trackingAreas { view.removeTrackingArea(a) }
        let p = pointer
        var rects = Array(trayRects.values)
        for (side, r) in wings where r.width > 0 && trayRects[side] == nil { rects.append(r) }
        for r in rects {
            var opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
            if r.contains(p) { opts.insert(.assumeInside) }
            view.addTrackingArea(NSTrackingArea(rect: r, options: opts, owner: view, userInfo: nil))
        }
        // Areas rebuilt under a resting pointer never report "entered"; check by hand.
        if side(at: p) != openSide { DispatchQueue.main.async { [weak self] in self?.pointerMoved() } }
    }

    private func side(at p: CGPoint) -> Side? {
        if let s = openSide, let r = trayRects[s], r.contains(p) { return s }
        return wings.first { $0.value.width > 0 && $0.value.contains(p) }?.key
    }

    func pointerMoved() {
        let s = side(at: pointer)
        if let s, bubble == nil {
            closeWork?.cancel()
            if s != openSide {
                openSide = s
                refreshTitles()
                render()
            }
        } else if openSide != nil {
            closeWork?.cancel()
            let w = DispatchWorkItem { [weak self] in
                guard let self, self.side(at: self.pointer) == nil else { return }
                self.openSide = nil
                self.render()
            }
            closeWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: w)
        }
    }

    func click(_ p: CGPoint) {
        guard let id = hits.first(where: { $0.value.contains(p) })?.key else { return }
        if let s = store.sessions(of: id).first { openChat(s) }
    }

    func openChat(_ s: Session) {
        for p in store.pending where p.session === s { store.release(p) }
        store.markSeen(s.agent)
        Focus.open(s, agent: config.agent(s.agent))
    }

    func showMenu(_ e: NSEvent, in v: NSView) {
        guard let m = menu?() else { return }
        NSMenu.popUpContextMenu(m, with: e, for: v)
    }
}
