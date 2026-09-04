import AppKit
import SwiftUI

/// Dónde aparecen los avisos breves de OmniMac.
enum ToastStyle: Int, CaseIterable {
    /// Una pastilla abajo, en el centro de la pantalla.
    case bottom = 0
    /// El notch se despliega un poco y enseña el aviso debajo.
    case notch = 1

    var title: String {
        switch self {
        case .bottom: "Abajo de la pantalla"
        case .notch: "Desplegando el notch"
        }
    }
}

/// Aviso breve («Texto copiado», «Micrófono silenciado»…). Según Ajustes, sale como
/// pastilla abajo o desplegando el notch; si el notch no está disponible (oculto por
/// pantalla completa, abierto, sin módulo), cae a la pastilla.
enum Toast {
    static let styleKey = "toast.style"

    static var style: ToastStyle {
        get { ToastStyle(rawValue: UserDefaults.standard.integer(forKey: styleKey)) ?? .bottom }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: styleKey) }
    }

    /// Lo instala el notch mientras existe: devuelve true si ha podido enseñar el aviso.
    static var notchPresenter: ((_ text: String, _ symbol: String, _ duration: TimeInterval, _ tint: NSColor?) -> Bool)?

    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ text: String, symbol: String, duration: TimeInterval = 1.6, tint: NSColor? = nil) {
        DispatchQueue.main.async {
            if style == .notch, let presenter = notchPresenter, presenter(text, symbol, max(duration, 2.2), tint) {
                return
            }
            showBottom(text, symbol: symbol, duration: duration, tint: tint)
        }
    }

    private static func showBottom(_ text: String, symbol: String, duration: TimeInterval, tint: NSColor?) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: ToastView(text: text, symbol: symbol, tint: tint.map { Color(nsColor: $0) }))
        let size = panel.contentView?.fittingSize ?? CGSize(width: 260, height: 44)
        let frame = CGRect(x: screen.visibleFrame.midX - size.width / 2,
                           y: screen.visibleFrame.minY + 48,
                           width: size.width,
                           height: size.height)
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.level = .screenSaver
        return panel
    }
}

struct ToastView: View {
    let text: String
    let symbol: String
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let tint {
                Circle()
                    .fill(tint)
                    .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                    .frame(width: 18, height: 18)
            }
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
            Text(text)
                .font(.system(size: 13.5, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .fixedSize()
    }
}
