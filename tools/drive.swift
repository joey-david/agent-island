// Synthetic pointer and keys for recording the demo: drive move X Y | click X Y | key CODE
import CoreGraphics
import Foundation
let a = CommandLine.arguments
func post(_ t: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
switch a[1] {
case "move":
    let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    post(.mouseMoved, CGPoint(x: p.x - 1, y: p.y)); usleep(40000); post(.mouseMoved, p)
case "click":
    let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    post(.mouseMoved, p); usleep(80000); post(.leftMouseDown, p); usleep(70000); post(.leftMouseUp, p)
case "key":
    for down in [true, false] {
        CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(Int(a[2])!), keyDown: down)?.post(tap: .cghidEventTap)
        usleep(30000)
    }
default: break
}
