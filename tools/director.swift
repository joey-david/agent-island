// Helpers for recording the demo on the real screen:
//   director backdrop IMAGE      full-screen wallpaper behind the demo windows (runs until killed)
//   director glide X Y [MS]      ease the real pointer to X,Y (top-left screen points)
//   director click X Y           glide there, then click
//   director key CODE            press and release a key
//   director scroll PIXELS [MS]  smooth scroll under the pointer (positive scrolls down)
//   director notch OUT W H SCALE MINX MAXX NH [TINT]
//                                a W x H point strip, in pixels at SCALE: the island's shape from MINX
//                                to MAXX filled black, or with TINT (hex) a soft glow around it
import AppKit

let a = CommandLine.arguments

func post(_ t: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func glide(to p: CGPoint, ms: Double) {
    let from = CGEvent(source: nil)?.location ?? p
    let steps = max(1, Int(ms / 8))
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        post(.mouseMoved, CGPoint(x: from.x + (p.x - from.x) * e, y: from.y + (p.y - from.y) * e))
        usleep(8000)
    }
}

switch a[1] {
case "glide":
    let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    let from = CGEvent(source: nil)?.location ?? p
    glide(to: p, ms: a.count > 4 ? Double(a[4])! : 450 + min(450, hypot(p.x - from.x, p.y - from.y) * 0.5))
case "click":
    let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    post(.leftMouseDown, p); usleep(90000); post(.leftMouseUp, p)
case "scroll":
    let total = Double(a[2])!, ms = a.count > 3 ? Double(a[3])! : 900
    let steps = max(1, Int(ms / 16))
    var done = 0.0
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let e = 1 - pow(1 - t, 3)
        let dy = (total * e - done).rounded()
        done += dy
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(-dy), wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
        usleep(16000)
    }
case "key":
    for down in [true, false] {
        CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(Int(a[2])!), keyDown: down)?.post(tap: .cghidEventTap)
        usleep(40000)
    }
case "backdrop":
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    guard let screen = NSScreen.screens.first, let img = NSImage(contentsOfFile: a[2]) else { exit(1) }
    let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.level = .normal
    // This space only: on every space it would cover full-screen apps too.
    w.collectionBehavior = [.stationary, .ignoresCycle]
    w.ignoresMouseEvents = true
    let v = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
    v.image = img
    v.imageScaling = .scaleAxesIndependently
    // Aspect-fill: crop the image's middle to the screen's shape.
    let ir = img.size.width / img.size.height, sr = screen.frame.width / screen.frame.height
    var crop = NSRect(origin: .zero, size: img.size)
    if ir > sr { crop.size.width = img.size.height * sr; crop.origin.x = (img.size.width - crop.width) / 2 }
    else { crop.size.height = img.size.width / sr; crop.origin.y = (img.size.height - crop.height) / 2 }
    let filled = NSImage(size: screen.frame.size)
    filled.lockFocus()
    img.draw(in: NSRect(origin: .zero, size: screen.frame.size), from: crop, operation: .copy, fraction: 1)
    filled.unlockFocus()
    v.image = filled
    w.contentView = v
    w.orderFrontRegardless()
    app.run()
case "notch":
    let (w, h, scale) = (Double(a[3])!, Double(a[4])!, Double(a[5])!)
    let (minX, maxX, nh) = (Double(a[6])!, Double(a[7])!, Double(a[8])!)
    let ctx = CGContext(data: nil, width: Int(w * scale), height: Int(h * scale), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Top-left origin, in points; the same outline as Island.shape.
    ctx.translateBy(x: 0, y: h * scale)
    ctx.scaleBy(x: scale, y: -scale)
    let (ear, R, bottom) = (6.0, min(12, nh / 2 - 2), nh)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: minX - ear, y: 0))
    p.addQuadCurve(to: CGPoint(x: minX, y: ear), control: CGPoint(x: minX, y: 0))
    p.addLine(to: CGPoint(x: minX, y: bottom - R))
    p.addCurve(to: CGPoint(x: minX + R, y: bottom), control1: CGPoint(x: minX, y: bottom - R * 0.45), control2: CGPoint(x: minX + R * 0.45, y: bottom))
    p.addLine(to: CGPoint(x: maxX - R, y: bottom))
    p.addCurve(to: CGPoint(x: maxX, y: bottom - R), control1: CGPoint(x: maxX - R * 0.45, y: bottom), control2: CGPoint(x: maxX, y: bottom - R * 0.45))
    p.addLine(to: CGPoint(x: maxX, y: ear))
    p.addQuadCurve(to: CGPoint(x: maxX + ear, y: 0), control: CGPoint(x: maxX, y: 0))
    p.closeSubpath()
    if a.count > 9, let v = UInt32(a[9], radix: 16) {
        let tint = CGColor(srgbRed: Double(v >> 16 & 255) / 255, green: Double(v >> 8 & 255) / 255, blue: Double(v & 255) / 255, alpha: 1)
        // Halo and a thin rim, then the island itself cut back out so only the outside glows.
        ctx.setShadow(offset: .zero, blur: 16 * scale, color: tint)
        for _ in 0..<2 { ctx.addPath(p); ctx.setFillColor(tint); ctx.fillPath() }
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.addPath(p); ctx.setStrokeColor(tint); ctx.setLineWidth(3); ctx.strokePath()
        ctx.setBlendMode(.clear)
    } else {
        ctx.setFillColor(.black)
    }
    ctx.addPath(p)
    ctx.fillPath()
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
default:
    break
}
