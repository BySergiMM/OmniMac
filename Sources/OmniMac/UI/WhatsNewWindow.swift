import AppKit
import SwiftUI

/// El recorrido de novedades que sale la primera vez que abres una versión nueva.
///
/// Se abre solo tras actualizar (ver `AppDelegate`) y también a mano desde el menú.
/// El contenido sale del `CHANGELOG.md` empaquetado con la app: basta con escribir la
/// novedad ahí y aparece aquí, una por pantalla.
final class WhatsNewWindowController: NSWindowController, NSWindowDelegate {
    static let shared = WhatsNewWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no soportado") }

    /// Las novedades de la versión que se está ejecutando. Si el archivo no trae esa
    /// versión exacta (una compilación de desarrollo, por ejemplo), la más nueva.
    static var currentNotes: ReleaseNotes? {
        // Cada idioma tiene su archivo. Si falta el inglés (una compilación vieja),
        // se cae al español antes que no enseñar nada.
        let names = Localization.isSpanish ? ["CHANGELOG"] : ["CHANGELOG.en", "CHANGELOG"]
        guard let url = names.lazy.compactMap({ Bundle.main.url(forResource: $0, withExtension: "md") }).first,
              let markdown = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return ReleaseNotes.notes(for: Brand.version, in: markdown)
            ?? ReleaseNotes.all(from: markdown).first
    }

    @discardableResult
    func showCurrent() -> Bool {
        guard let notes = Self.currentNotes, !notes.highlights.isEmpty else { return false }
        window?.contentView = NSHostingView(rootView: WhatsNewView(notes: notes) { [weak self] in
            self?.close()
        })
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil   // que SwiftUI suelte la vista
    }
}

/// El recorrido: una portada y después una novedad por pantalla.
struct WhatsNewView: View {
    let notes: ReleaseNotes
    let onClose: () -> Void

    @State private var page = 0
    /// Hacia dónde va la animación (para que al retroceder entre por el otro lado).
    @State private var forward = true

    /// Portada + una pantalla por novedad.
    private var pageCount: Int { notes.highlights.count + 1 }
    private var isLast: Bool { page == pageCount - 1 }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 36)

            dots
                .padding(.bottom, 18)

            Divider()

            HStack {
                if !isLast {
                    Button(L("Saltar", "Skip"), action: onClose)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(isLast ? L("Listo", "Done") : L("Siguiente", "Next")) {
                    if isLast {
                        onClose()
                    } else {
                        forward = true
                        withAnimation(.easeInOut(duration: 0.22)) { page += 1 }
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 480, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Brand.accent)
        // ← y → para moverse, Esc para cerrar.
        .onKeyPress(.leftArrow) { back(); return .handled }
        .onKeyPress(.rightArrow) { advance(); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            if page == 0 {
                cover.transition(transition)
            } else {
                highlight(notes.highlights[page - 1]).transition(transition)
            }
        }
    }

    private var transition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    // MARK: - Pantallas

    private var cover: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 92, height: 92)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .padding(.bottom, 6)
            Text(L("Novedades de OmniMac", "What's new in OmniMac"))
                .font(.system(size: 26, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(count)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    private func highlight(_ item: ReleaseNotes.Highlight) -> some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Brand.gradient)
                .frame(width: 92, height: 92)
                .overlay(
                    Image(systemName: item.symbol)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(.white)
                )
                .shadow(color: Brand.accent.opacity(0.35), radius: 12, y: 5)

            Text(item.title)
                .font(.system(size: 22, weight: .semibold))
                .multilineTextAlignment(.center)

            Text(item.detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == page ? Brand.accent : Color.secondary.opacity(0.28))
                    .frame(width: 7, height: 7)
                    .onTapGesture {
                        forward = index > page
                        withAnimation(.easeInOut(duration: 0.22)) { page = index }
                    }
            }
        }
    }

    // MARK: - Moverse

    private func advance() {
        guard page < pageCount - 1 else { return }
        forward = true
        withAnimation(.easeInOut(duration: 0.22)) { page += 1 }
    }

    private func back() {
        guard page > 0 else { return }
        forward = false
        withAnimation(.easeInOut(duration: 0.22)) { page -= 1 }
    }

    /// «1 novedad» / «3 novedades», que el plural mal puesto canta mucho.
    private var count: String {
        let n = notes.highlights.count
        return n == 1
            ? L("1 novedad en esta versión.", "1 new thing in this version.")
            : L("\(n) novedades en esta versión.", "\(n) new things in this version.")
    }

    private var subtitle: String {
        guard let date = notes.date, let pretty = Self.pretty(date) else {
            return L("Versión \(notes.version)", "Version \(notes.version)")
        }
        return L("Versión \(notes.version) · \(pretty)", "Version \(notes.version) · \(pretty)")
    }

    /// «2026-09-06» → «6 de septiembre de 2026» (o su equivalente en inglés).
    private static func pretty(_ raw: String) -> String? {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: raw) else { return nil }
        let out = DateFormatter()
        out.dateStyle = .long
        out.timeStyle = .none
        out.locale = Locale(identifier: Localization.isSpanish ? "es_ES" : "en_GB")
        return out.string(from: date)
    }
}
