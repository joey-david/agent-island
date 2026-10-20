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
    override func mouseMoved(with e: NSEvent) { controller?.pointerMoved() }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with e: NSEvent) { if controller?.key(e) != true { super.keyDown(with: e) } }
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
    private var height: CGFloat = 520
    /// The island draws on a fixed 520pt canvas pinned to the top of the window; the window itself
    /// stays a notch-high strip and only grows while a question panel is open, so the compositor
    /// isn't blending a big transparent sheet over whatever is underneath.
    private let holder = NSView()
    private var screenTop: CGFloat = 0, screenX: CGFloat = 0, screenW: CGFloat = 0
    private var windowTall = true
    private var shrinkToken = 0
    private var hovers: [Side: CGRect] = [:]
    private var visible = false
    private var hideToken = 0
    /// Hidden along with the menu bar (full screen, or auto-hide): back when it slides down,
    /// for a question, or for a moment when an agent finishes.
    private var hushed = false
    private var menuBarDown = true
    private var flashUntil = Date.distantPast
    private var finished: Set<String> = []
    private var barTimer: DispatchSourceTimer?
    private var revealUntil = Date.distantPast
    private var screenID: CGDirectDisplayID = 0
    private var bubble: BubbleView?
    private var openSide: Side?
    /// Session previewed in the tray per agent (hovering its pip), and where those pips are.
    private var selected: [String: String] = [:]
    private var pipHits: [(rect: CGRect, key: String)] = []
    /// Agent picked with the arrow keys while a tray is open, and the app to hand keys back to.
    private var keyFocus: String?
    private var keyOwner: NSRunningApplication?
    private var tray: TrayView?
    private var trayKey = ""
    private var closeWork: DispatchWorkItem?
    private let store: SessionStore
    private let config: ConfigStore
    var menu: (() -> NSMenu)?

    private let pad: CGFloat = 12, gap: CGFloat = 10, stackStep: CGFloat = 11, maxStack = 4
    private var bodyH: CGFloat { (notch.height * 0.56).rounded() }
    /// The window pokes a few points above the screen so the topmost pixel row, where a pointer
    /// pinned to the edge sits, is inside it rather than on its border.
    private let overscan: CGFloat = 4
    private var top: CGFloat { height - overscan }

    init(store: SessionStore, config: ConfigStore) {
        self.store = store
        self.config = config
        super.init()
        window.contentView = holder
        holder.addSubview(view)
        window.acceptsMouseMovedEvents = true
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
        watchMenuBar()
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
        // The physical notch runs about a point below the safe area; cover it fully.
        let nh = inset > 0 ? inset + 1 : max(24, f.maxY - screen.visibleFrame.maxY)
        var nx = f.width / 2 - 90, nw: CGFloat = 180
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            let origin = l.minX >= f.minX - 1 ? f.minX : 0
            nx = l.maxX - origin
            nw = r.minX - l.maxX
        }
        screenTop = f.maxY
        screenID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        screenX = f.minX
        screenW = f.width
        view.frame = NSRect(x: 0, y: 0, width: f.width, height: height)
        host.frame = view.bounds
        for l in [root, slotLayer, mask] { l.frame = view.bounds }
        for l in [root, bar, barMask, panel, slotLayer] + Array(trays.values) + Array(trayMasks.values) {
            l.contentsScale = screen.backingScaleFactor
        }
        notch = CGRect(x: nx, y: top - nh, width: nw, height: nh)
        fitWindow(tall: store.pending.first != nil)
        for s in slots.values { s.layer.removeFromSuperlayer() }
        slots.removeAll()
        collapse()
    }

    private func fitWindow(tall: Bool) {
        let h = tall ? height : notch.height + overscan + 10
        windowTall = tall
        window.setFrame(NSRect(x: screenX, y: screenTop + overscan - h, width: screenW, height: h), display: false)
        view.setFrameOrigin(NSPoint(x: 0, y: h - height))
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
        let done = Set(store.sessions.values.filter { store.displayState($0) == .done }.map(\.key))
        if !done.subtracting(finished).isEmpty && !menuBarDown { flash() }
        finished = done
        hush(!menuBarDown && pending == nil && Date() >= flashUntil)
        if pending != nil, !windowTall {
            fitWindow(tall: true)
        } else if pending == nil, windowTall {
            shrinkToken += 1
            let token = shrinkToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self, token == self.shrinkToken, self.store.pending.isEmpty else { return }
                self.fitWindow(tall: false)
            }
        }
        if show && !visible {
            visible = true
            collapse()
            if !hushed { window.orderFrontRegardless() }
        }
        if openSide.map({ sides[$0]!.isEmpty }) ?? false { openSide = nil }

        // Collapsed wings: bodies sit in a row, popping out from under the notch.
        var targets: [String: (center: CGPoint, scale: CGFloat)] = [:]
        hits = [:]
        let cy = notch.midY
        var edges: [Side: CGFloat] = [:]
        for side in [Side.left, .right] {
            let dir: CGFloat = side == .left ? -1 : 1
            var x = side == .left ? notch.minX - pad : notch.maxX + pad
            for (a, sum) in sides[side]! {
                let sp = SpriteLibrary.sprite(for: a)
                let w = (bodyH * sp.weight * sp.bodyAspect).rounded()
                // Extra sessions tuck in behind the front mascot, a few points each.
                let gw = w + CGFloat(min(sum.count, maxStack) - 1) * stackStep
                let cx = x + dir * w / 2
                targets[a.id] = (CGPoint(x: cx, y: cy), 1)
                hits[a.id] = CGRect(x: min(x, x + dir * gw) - gap / 2, y: notch.minY, width: gw + gap, height: notch.height)
                x += dir * (gw + gap)
            }
            edges[side] = sides[side]!.isEmpty ? (side == .left ? notch.minX : notch.maxX) : x - dir * gap + dir * pad
        }
        let minX = edges[.left]!, maxX = edges[.right]!
        wings = [.left: CGRect(x: minX, y: notch.minY, width: notch.minX - minX, height: notch.height),
                 .right: CGRect(x: notch.maxX, y: notch.minY, width: maxX - notch.maxX, height: notch.height)]
        // Hover targets run into the notch and meet in its middle.
        hovers = [:]
        if minX < notch.minX { hovers[.left] = CGRect(x: minX, y: notch.minY, width: notch.midX - minX, height: notch.height) }
        if maxX > notch.maxX { hovers[.right] = CGRect(x: notch.midX, y: notch.minY, width: maxX - notch.midX, height: notch.height) }
        let barPath = shape(minX, maxX, notch.minY, barRadius)
        set(bar, barPath, animated: animated)
        set(barMask, barPath, animated: animated)

        // The hovered side widens into a tray at notch height; a question then drops below it.
        if let pending, let side = config.agent(pending.session.agent)?.placement, side != .hidden, !sides[side]!.isEmpty {
            openSide = side
        }
        trayRects = [:]
        var openRows: [TrayView.Row] = []
        for side in [Side.left, .right] {
            let rows = sides[side]!
            let path: CGPath
            if side == openSide {
                openRows = trayRows(rows)
                let widths = openRows.map(TrayView.width)
                let w = max(widths.reduce(TrayView.inset, +), wings[side]!.width)
                let r = side == .left ? CGRect(x: notch.minX - w, y: notch.minY, width: w, height: notch.height)
                                      : CGRect(x: notch.maxX, y: notch.minY, width: w, height: notch.height)
                trayRects[side] = r
                path = side == .left ? shape(r.minX, notch.maxX, notch.minY, barRadius) : shape(notch.minX, r.maxX, notch.minY, barRadius)
                for (i, (a, _)) in rows.enumerated() {
                    let seg = TrayView.segment(i, side: side, in: r, widths: widths)
                    let ix = side == .left ? seg.minX + TrayView.edge + TrayView.iconW / 2 : seg.maxX - TrayView.edge - TrayView.iconW / 2
                    targets[a.id] = (CGPoint(x: ix, y: notch.midY), 1)
                    hits[a.id] = seg
                }
            } else {
                path = side == .left ? shape(minX, notch.maxX, notch.minY, barRadius) : shape(notch.minX, maxX, notch.minY, barRadius)
            }
            set(trays[side]!, path, animated: animated)
            set(trayMasks[side]!, path, animated: animated)
        }
        updateTrayView(openRows)

        // Questions: the island morphs wider and taller in one spring (the asking side widens with
        // it), and the content fades up into place partway through.
        if let pending {
            var span = (min: notch.midX - 210, max: notch.midX + 210)
            if let side = openSide, let r = trayRects[side] {
                span = side == .left ? (r.minX, notch.maxX) : (notch.minX, r.maxX)
            }
            if bubble?.pending !== pending { presentBubble(pending, width: span.max - span.min) }
            let size = bubble!.preferredSize
            bubble!.frame = CGRect(x: span.min, y: notch.minY - size.height, width: size.width, height: size.height)
            set(panel, shape(span.min, span.max, notch.minY - size.height, 22), animated: animated)
        } else {
            dismissBubble()
            set(panel, notchPath, animated: animated)
        }

        // One mascot per session: the most urgent (or previewed) in front, the rest stacked behind it.
        var live = Set<String>()
        for side in [Side.left, .right] {
            let dir: CGFloat = side == .left ? -1 : 1
            for (a, _) in sides[side]! {
                let t = targets[a.id]!
                let sprite = SpriteLibrary.sprite(for: a)
                var ss = Array(store.sessions(of: a.id))
                if let k = selected[a.id], let i = ss.firstIndex(where: { $0.key == k }) { ss.insert(ss.remove(at: i), at: 0) }
                for (k, s) in ss.prefix(maxStack).enumerated() {
                    live.insert(s.key)
                    let slot: Slot
                    if let old = slots[s.key], !old.leaving {
                        slot = old
                        if slot.sprite !== sprite { slot.sprite = sprite; dress(slot); slot.anim = nil }
                    } else {
                        slots[s.key]?.layer.removeFromSuperlayer()
                        slot = Slot(id: s.key, sprite: sprite)
                        dress(slot)
                        slot.layer.position = behindNotch(sprite, left: side == .left)
                        slotLayer.addSublayer(slot.layer)
                        slots[s.key] = slot
                    }
                    let back = CGFloat(k)
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    slot.layer.zPosition = -back
                    CATransaction.commit()
                    fade(slot.layer, to: k == 0 ? 1 : Float(max(0.22, 0.55 - 0.15 * back)), animated: animated)
                    move(slot.layer, to: CGPoint(x: t.center.x + dir * back * stackStep * t.scale, y: t.center.y), animated: animated)
                    scale(slot.layer, to: t.scale * (k == 0 ? 1 : 0.8), animated: animated)
                    apply(slot, store.displayState(s), front: k == 0)
                }
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

    private func apply(_ slot: Slot, _ state: AgentState, front: Bool) {
        let anim: Anim
        switch state {
        case .question: anim = .question
        case .working: anim = .working
        case .done: anim = .done
        case .idle: anim = .idle
        }
        if slot.anim != anim {
            slot.anim = anim
            play(slot)
        }
        slot.dot.isHidden = !front
        guard slot.dotState != state else { return }
        slot.dotState = state
        slot.dot.removeAllAnimations()
        switch state {
        case .question:
            slot.dot.backgroundColor = NSColor.systemOrange.cgColor
            slot.dot.opacity = 1
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.25
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 15)
            slot.dot.add(pulse, forKey: "pulse")
        case .done:
            slot.dot.backgroundColor = NSColor.systemGreen.cgColor
            slot.dot.opacity = 1
        default:
            slot.dot.opacity = 0
        }
    }

    static func color(_ s: AgentState, tint: NSColor) -> NSColor {
        switch s {
        case .question: return .systemOrange
        case .working: return tint
        case .done: return .systemGreen
        case .idle: return NSColor(white: 1, alpha: 0.28)
        }
    }

    private func play(_ slot: Slot) {
        let l = slot.layer, s = slot.sprite
        l.removeAnimation(forKey: "frames")
        l.removeAnimation(forKey: "once")
        guard let anim = slot.anim else { return }
        // Idle fidgets a few times, then holds still on its first frame: resting mascots cost nothing.
        switch anim {
        case .done:
            l.add(track(s, .idle, repeats: 3), forKey: "frames")
            l.add(track(s, .done, repeats: 2), forKey: "once")
        case .idle:
            l.add(track(s, .idle, repeats: 2), forKey: "frames")
        default:
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
        k.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: 12, preferred: 10)  // frames hold ≥110ms
        return k
    }

    // MARK: tray

    private func trayRows(_ agents: [(AgentConfig, AgentSummary)]) -> [TrayView.Row] {
        agents.map { a, sum in
            let ss = store.sessions(of: a.id)
            let i = ss.firstIndex { $0.key == selected[a.id] } ?? 0
            let s = ss.isEmpty ? nil : ss[i]
            return TrayView.Row(agent: a, state: s.map(store.displayState) ?? sum.state, session: s, usage: Usage.read(a.id),
                                states: ss.map(store.displayState), sessions: ss, keys: ss.map(\.key), selected: i, focused: keyFocus == a.id,
                                switching: ss.count > 1 && selected[a.id] != nil)
        }
    }

    private func updateTrayView(_ rows: [TrayView.Row]) {
        guard let side = openSide, let r = trayRects[side] else {
            trayKey = ""
            pipHits = []
            selected = [:]
            keyFocus = nil
            releaseKeys()
            if let t = tray {
                tray = nil
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.08; t.animator().alphaValue = 0 }, completionHandler: { t.removeFromSuperview() })
            }
            return
        }
        // Rebuild only when something visible changed.
        let key = "\(side)|\(r)|" + rows.map {
            "\($0.agent.id)\($0.state)\($0.keys)\($0.states)\($0.selected)\($0.focused)\($0.switching)\($0.session?.action ?? "")\($0.session?.title ?? "")\($0.session?.prompt ?? "")\(Int($0.usage?.fiveHour ?? -1))"
        }.joined(separator: "|") + "\(rows.map(TrayView.width))"
        guard key != trayKey else { return }
        let fresh = tray == nil || !trayKey.hasPrefix("\(side)|")
        trayKey = key
        tray?.removeFromSuperview()
        let t = TrayView(frame: r, side: side, rows: rows)
        view.addSubview(t)
        tray = t
        pipHits = t.pips.map { (view.convert($0.rect, from: t), $0.key) }
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

    private func fade(_ l: CALayer, to o: Float, animated: Bool) {
        let from = l.presentation()?.opacity ?? l.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.opacity = o
        CATransaction.commit()
        guard animated, abs(from - o) > 0.01 else { return }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = o
        a.duration = 0.25
        l.add(a, forKey: "opacity")
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

    private func presentBubble(_ p: Pending, width: CGFloat) {
        bubble?.removeFromSuperview()
        let agent = config.agent(p.session.agent) ?? AgentConfig(id: p.session.agent)
        let b = BubbleView(pending: p, agent: agent, sprite: SpriteLibrary.sprite(for: agent), width: max(360, width))
        b.onAnswer = { [weak self] out in self?.store.answer(p, output: out) }
        b.onChat = { [weak self] in self?.openChat(p.session) }
        b.onResize = { [weak self] in self?.render() }
        b.alphaValue = 0
        b.wantsLayer = true
        view.addSubview(b)
        bubble = b
        // Content rises out of the growing shape: fade in with a slight lift once it has room.
        let lift = CABasicAnimation(keyPath: "transform")
        lift.fromValue = CATransform3DMakeTranslation(0, 6, 0)
        lift.toValue = CATransform3DIdentity
        lift.duration = 0.32
        lift.beginTime = CACurrentMediaTime() + 0.17
        lift.fillMode = .backwards
        lift.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        b.layer?.add(lift, forKey: "lift")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) {
            NSAnimationContext.runAnimationGroup {
                $0.duration = 0.24
                $0.timingFunction = CAMediaTimingFunction(name: .easeOut)
                b.animator().alphaValue = 1
            }
        }
    }

    private func dismissBubble() {
        guard let b = bubble else { return }
        bubble = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.1; b.animator().alphaValue = 0 }, completionHandler: { b.removeFromSuperview() })
    }

    // MARK: input

    /// Pointer in island coordinates; anything above the screen's top counts as its top row.
    private var pointer: CGPoint {
        let p = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return CGPoint(x: p.x, y: min(p.y, top - 0.5))
    }

    private func trackPointer() {
        for a in view.trackingAreas { view.removeTrackingArea(a) }
        let p = pointer
        var rects = trayRects.map { $0.value.union(hovers[$0.key] ?? $0.value) }
        for (side, r) in hovers where trayRects[side] == nil { rects.append(r) }
        if openSide != nil { rects += pipHits.map(\.rect) }
        // One area over the whole island that also reports movement inside it, so the open side
        // always follows the pointer, however fast it crosses the notch. Silent once outside.
        if var all = rects.first.map({ rects.dropFirst().reduce($0) { $0.union($1) } }) {
            all.size.height = height - all.minY   // up through the overscan, to the window's top
            var opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways]
            if all.contains(p) { opts.insert(.assumeInside) }
            view.addTrackingArea(NSTrackingArea(rect: all, options: opts, owner: view, userInfo: nil))
        }
        // Areas rebuilt under a resting pointer never report "entered"; check by hand.
        if side(at: p) != openSide { DispatchQueue.main.async { [weak self] in self?.pointerMoved() } }
    }

    private func side(at p: CGPoint) -> Side? {
        if let s = openSide, let r = trayRects[s], r.union(hovers[s] ?? r).contains(p) { return s }
        return hovers.first { $0.value.contains(p) }?.key
    }

    func pointerMoved() {
        let s = side(at: pointer)
        if store.pending.first != nil { return }
        if let s {
            closeWork?.cancel()
            if s != openSide {
                openSide = s
                selected = [:]
                keyFocus = nil
                takeKeys()
                refreshTitles()
                // Looking counts as reading: finished sessions on this side go quiet.
                for a in config.config.agents where a.placement == s { store.markSeen(a.id) }
                render()
            } else if let hit = pipHits.first(where: { $0.rect.contains(pointer) }), let sess = store.sessions[hit.key],
                      selected[sess.agent] != hit.key {
                selected[sess.agent] = hit.key
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

    // MARK: menu bar

    /// Follows the menu bar on the island's screen. Where macOS auto-hides it (by default in
    /// full-screen spaces), the island hides too and comes back when the pointer reaches the top
    /// edge, staying while it's within the bar or the island. The window list can't tell a hidden
    /// menu bar from a shown one, so this mirrors the rule rather than watching the bar.
    private func watchMenuBar() {
        let ws = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            ws.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                self?.updateAutoHide()
                // The space's type can settle after the switch animation.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.updateAutoHide() }
            }
        }
        updateAutoHide()
    }

    private func updateAutoHide() {
        let hides = Spaces.isFullScreen(screenID) ? Spaces.menuBarHidesInFullScreen : Spaces.menuBarHidesOnDesktop
        if hides, barTimer == nil {
            let t = DispatchSource.makeTimerSource(queue: .main)
            t.schedule(deadline: .now(), repeating: 0.1, leeway: .milliseconds(30))
            t.setEventHandler { [weak self] in self?.checkMenuBar() }
            t.resume()
            barTimer = t
            menuBarDown = false
            render()
        } else if !hides, let t = barTimer {
            t.cancel()
            barTimer = nil
            menuBarDown = true
            render()
        }
    }

    private func checkMenuBar() {
        let m = NSEvent.mouseLocation
        let across = m.x >= screenX && m.x <= screenX + screenW
        let p = view.convert(window.convertPoint(fromScreen: m), from: nil)
        let down: Bool
        if across && m.y >= screenTop - 1 { down = true }
        else if menuBarDown && across && (m.y >= screenTop - notch.height - 4 || (!hushed && side(at: p) != nil)) { down = true }
        else { down = false }
        if down { revealUntil = Date() + 0.4 }
        let next = down || Date() < revealUntil
        guard next != menuBarDown else { return }
        menuBarDown = next
        render()
    }

    /// Something just finished while the island is hidden: pop in, then go again.
    private func flash() {
        flashUntil = Date() + 2.5
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in self?.render() }
    }

    private func hush(_ on: Bool) {
        guard on != hushed else { return }
        hushed = on
        if on { openSide = nil }
        // Fade, then take the window off screen. (Setting ignoresMouseEvents instead would end the
        // click-through of its transparent parts for good, and the window spans the menu bar.)
        if !on && visible { window.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup({ $0.duration = on ? 0.25 : 0.18; window.animator().alphaValue = on ? 0 : 1 }) { [weak self] in
            guard let self, self.hushed else { return }
            self.window.orderOut(nil)
        }
    }

    // MARK: keyboard

    /// While a tray is open the island takes the keyboard (without activating the app),
    /// so ←/→ walk every session on that side, Return opens it, Esc closes.
    private func takeKeys() {
        guard !window.isKeyWindow else { return }
        keyOwner = NSWorkspace.shared.frontmostApplication
        window.makeKey()
        window.makeFirstResponder(view)
    }

    private func releaseKeys() {
        guard window.isKeyWindow, bubble == nil else { return }
        window.resignKey()
        keyOwner?.activate()
        keyOwner = nil
    }

    /// The open side's sessions in on-screen left-to-right order.
    private func visualOrder() -> [(agent: String, key: String)] {
        guard let side = openSide else { return [] }
        var agents = config.config.agents.filter { $0.placement == side && store.summary($0.id) != nil }
        if side == .left { agents.reverse() }
        return agents.flatMap { a -> [(agent: String, key: String)] in
            let keys = store.sessions(of: a.id).prefix(6).map { (a.id, $0.key) }
            return side == .left ? Array(keys) : keys.reversed()
        }
    }

    func key(_ e: NSEvent) -> Bool {
        guard openSide != nil else { return false }
        switch e.keyCode {
        case 123, 124: // ← →
            let order = visualOrder()
            guard !order.isEmpty else { return true }
            let cur = keyFocus.flatMap { f in order.firstIndex { $0.agent == f && $0.key == (selected[f] ?? store.sessions(of: f).first?.key) } }
            let next = cur.map { ($0 + (e.keyCode == 124 ? 1 : -1) + order.count) % order.count } ?? (e.keyCode == 124 ? 0 : order.count - 1)
            keyFocus = order[next].agent
            selected[order[next].agent] = order[next].key
            render()
        case 36, 76: // Return
            let id = keyFocus ?? visualOrder().first?.agent
            if let id {
                let ss = store.sessions(of: id)
                if let s = ss.first(where: { $0.key == selected[id] }) ?? ss.first { openChat(s) }
            }
        case 53: // Esc
            openSide = nil
            render()
        default:
            return false
        }
        return true
    }

    func click(_ raw: CGPoint) {
        let p = CGPoint(x: raw.x, y: min(raw.y, top - 0.5))
        if let hit = pipHits.first(where: { $0.rect.contains(p) }), let s = store.sessions[hit.key] { return openChat(s) }
        // Anywhere else that hovers a side (padding, gaps, its half of the notch) clicks through to
        // that side's agent: the one picked with the arrows, else the one nearest the notch.
        var id = hits.first(where: { $0.value.contains(p) })?.key
        if id == nil, let side = side(at: p) {
            let mine = config.config.agents.filter { $0.placement == side && store.summary($0.id) != nil }.map(\.id)
            id = mine.first { $0 == keyFocus } ?? mine.first
        }
        guard let id else { return }
        let ss = store.sessions(of: id)
        if let s = ss.first(where: { $0.key == selected[id] }) ?? ss.first { openChat(s) }
    }

    func openChat(_ s: Session) {
        for p in store.pending where p.session === s { store.release(p) }
        store.markSeen(s.agent)
        Focus.open(s, agent: config.agent(s.agent))
    }

    // MARK: demo driver

    /// Where an agent's front mascot is, in view coordinates.
    func mascot(_ agent: String) -> CGPoint? {
        store.sessions(of: agent).lazy.compactMap { self.slots[$0.key]?.layer.position }.first
    }

    /// Centre of the question panel's button labelled `title`.
    func button(_ title: String) -> CGPoint? {
        func find(_ v: NSView) -> NSView? {
            if let b = v as? HoverButton, Self.labels(b).contains(title) { return b }
            for s in v.subviews { if let f = find(s) { return f } }
            return nil
        }
        guard let b = bubble.flatMap(find) else { return nil }
        let r = view.convert(b.bounds, from: b)
        return CGPoint(x: r.midX, y: r.midY)
    }

    /// For the demo driver: `mascot:<agent>`, `button:<label>` or `pip:<agent>:<n>` as a screen point (top-left origin,
    /// as CGEvent wants), or `state` for sessions and pending questions. JSON either way.
    func locate(_ what: String) -> String {
        func json(_ o: Any) -> String { (try? JSONSerialization.data(withJSONObject: o)).map { String(decoding: $0, as: UTF8.self) } ?? "{}" }
        if what == "state" {
            let ss = store.sessions.values.map { ["key": $0.key, "agent": $0.agent, "state": "\(store.displayState($0))"] }
            return json(["sessions": ss, "pending": store.pending.count, "open": openSide.map { "\($0)" } ?? "", "hushed": hushed])
        }
        let parts = what.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return "{}" }
        var p: CGPoint?
        switch parts[0] {
        case "mascot": p = mascot(parts[1])
        case "button": p = button(parts[1])
        case "pip":   // pip:<agent>:<n>, the agent's n-th session dot in the open tray
            let q = parts[1].split(separator: ":").map(String.init)
            let mine = pipHits.filter { store.sessions[$0.key]?.agent == q.first }
            if q.count == 2, let n = Int(q[1]), n < mine.count { p = CGPoint(x: mine[n].rect.midX, y: notch.midY + 7.5) }
        default: break
        }
        guard let p else { return "{}" }
        let s = window.convertPoint(toScreen: view.convert(p, to: nil))
        let h = NSScreen.screens.first?.frame.height ?? 0
        return json(["x": s.x, "y": h - s.y])
    }

    private static func labels(_ v: NSView) -> [String] {
        ((v as? NSTextField).map { [$0.stringValue] } ?? []) + v.subviews.flatMap(labels)
    }

    func showMenu(_ e: NSEvent, in v: NSView) {
        guard let m = menu?() else { return }
        NSMenu.popUpContextMenu(m, with: e, for: v)
    }
}
