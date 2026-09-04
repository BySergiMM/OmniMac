import AppKit

/// Una ventana que puede aparecer en el selector ⌘Tab.
struct SwitcherWindow: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let icon: NSImage?
    let isMinimized: Bool
    let axElement: AXUIElement
}

enum WindowEnumerator {
    /// Devuelve las ventanas abiertas: primero las visibles en orden de apilamiento
    /// (la más reciente primero) y después las de otros espacios y las minimizadas.
    static func windows(includeMinimized: Bool) -> [SwitcherWindow] {
        let myPID = NSRunningApplication.current.processIdentifier

        // Orden de apilamiento según CoreGraphics (solo ventanas visibles del espacio actual).
        var zOrder: [CGWindowID: Int] = [:]
        let cgInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] ?? []
        var index = 0
        for entry in cgInfo {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = entry[kCGWindowNumber as String] as? Int else { continue }
            let windowID = CGWindowID(number)
            if zOrder[windowID] == nil {
                zOrder[windowID] = index
                index += 1
            }
        }

        // Ventanas reales vía Accesibilidad (incluye minimizadas y otros espacios).
        var result: [SwitcherWindow] = []
        var seen = Set<CGWindowID>()
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != myPID {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.25)

            for axWindow in AX.elements(axApp, kAXWindowsAttribute as String) {
                guard AX.string(axWindow, kAXSubroleAttribute as String) == kAXStandardWindowSubrole as String else { continue }
                let minimized = AX.bool(axWindow, kAXMinimizedAttribute as String)
                if minimized && !includeMinimized { continue }
                guard let windowID = AX.windowID(axWindow), !seen.contains(windowID) else { continue }
                seen.insert(windowID)

                let axTitle = AX.string(axWindow, kAXTitleAttribute as String) ?? ""
                let appName = app.localizedName ?? "App"
                result.append(SwitcherWindow(id: windowID,
                                             pid: app.processIdentifier,
                                             appName: appName,
                                             title: axTitle.isEmpty ? appName : axTitle,
                                             icon: app.icon,
                                             isMinimized: minimized,
                                             axElement: axWindow))
            }
        }

        result.sort { a, b in
            switch (zOrder[a.id], zOrder[b.id]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                if a.isMinimized != b.isMinimized { return !a.isMinimized }
                return a.appName.localizedCaseInsensitiveCompare(b.appName) == .orderedAscending
            }
        }
        return result
    }

    /// Trae la ventana al frente (desminimiza si hace falta) y activa su app.
    static func focus(_ window: SwitcherWindow) {
        if window.isMinimized {
            AX.set(window.axElement, kAXMinimizedAttribute as String, to: kCFBooleanFalse)
        }
        AXUIElementPerformAction(window.axElement, kAXRaiseAction as CFString)
        AX.set(window.axElement, kAXMainAttribute as String, to: kCFBooleanTrue)
        NSRunningApplication(processIdentifier: window.pid)?.activate()
    }
}
