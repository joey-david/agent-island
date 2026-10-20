import AppKit

@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray

/// Which kind of space a display is showing, and when macOS auto-hides the menu bar.
enum Spaces {
    /// A native full-screen app's space (SkyLight type 4) is current on that display.
    static func isFullScreen(_ display: CGDirectDisplayID) -> Bool {
        guard let all = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] else { return false }
        let uuid = CGDisplayCreateUUIDFromDisplayID(display).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
        let mine = all.first { ($0["Display Identifier"] as? String) == uuid }
            ?? all.first { ($0["Display Identifier"] as? String) == "Main" && display == CGMainDisplayID() }
            ?? (all.count == 1 ? all.first : nil)
        return (mine?["Current Space"] as? [String: Any])?["type"] as? Int == 4
    }

    /// System Settings › Menu Bar › "Automatically hide and show the menu bar":
    /// 0 always, 1 on desktop only, 2 in full screen only, 3 never.
    private static var option: Int? { UserDefaults.standard.object(forKey: "AutoHideMenuBarOption") as? Int }

    static var menuBarHidesInFullScreen: Bool {
        if let o = option { return o == 0 || o == 2 }
        return UserDefaults.standard.object(forKey: "AppleMenuBarVisibleInFullscreen") as? Bool != true
    }

    static var menuBarHidesOnDesktop: Bool {
        if let o = option { return o == 0 || o == 1 }
        return UserDefaults.standard.bool(forKey: "_HIHideMenuBar")
    }
}
