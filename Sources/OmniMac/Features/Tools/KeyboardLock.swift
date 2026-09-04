import AppKit
import SwiftUI

/// Bloquea el teclado unos segundos para limpiarlo: un tap se traga todas las teclas
/// y un velo enseña la cuenta atrás. Un clic desbloquea antes de tiempo. Un
/// temporizador de seguridad quita el tap pase lo que pase.
final class KeyboardLock {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var overlay: NSPanel?
    private var countdown: Timer?
    private var safety: DispatchWorkItem?
    private var onUnlock: (() -> Void)?
    private let model = KeyboardLockModel()

    func lock(seconds: Int, onUnlock: @escaping () -> Void) {
        guard tap == nil else { return }
        guard Permissions.hasAccessibility else {
            Permissions.requestAccessibility()
            Toast.show(L("Necesita el permiso de Accesibilidad", "Needs the Accessibility permission"), symbol: "exclamationmark.shield.fill")
            onUnlock()
            return
        }
        let mask: CGEventMask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                return Unmanaged.passUnretained(event)
            }
            return nil // tecla tragada
        }, userInfo: nil) else {
            onUnlock()
            return
        }
        self.tap = tap
        self.onUnlock = onUnlock
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        model.remaining = seconds
        showOverlay()
        countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.model.remaining -= 1
            if self.model.remaining <= 0 { self.unlock() }
        }
        let work = DispatchWorkItem { [weak self] in self?.unlock() }
        safety = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds + 2), execute: work)
    }

    func unlock() {
        countdown?.invalidate()
        countdown = nil
        safety?.cancel()
        safety = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        source = nil
        let wasLocked = tap != nil
        tap = nil
        overlay?.orderOut(nil)
        overlay = nil
        if wasLocked {
            onUnlock?()
            onUnlock = nil
        }
    }

    private func showOverlay() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let panel = NSPanel(contentRect: screen.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.level = .screenSaver
        let view = KeyboardLockView(model: model) { [weak self] in self?.unlock() }
        panel.contentView = FirstClickHostingView(rootView: view)
        panel.orderFrontRegardless()
        overlay = panel
    }
}

final class KeyboardLockModel: ObservableObject {
    @Published var remaining = 30
}

struct KeyboardLockView: View {
    @ObservedObject var model: KeyboardLockModel
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "keyboard")
                .font(.system(size: 54, weight: .light))
            Text(L("Teclado bloqueado", "Keyboard locked"))
                .font(.system(size: 26, weight: .bold))
            Text("\(model.remaining)")
                .font(.system(size: 64, weight: .heavy, design: .rounded).monospacedDigit())
            Text(L("Limpia tranquilo. Haz clic en cualquier sitio para desbloquear.", "Clean away. Click anywhere to unlock."))
                .font(.system(size: 14))
                .opacity(0.75)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
