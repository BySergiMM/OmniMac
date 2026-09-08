import AppKit
import SwiftUI

/// Ajustes › Limpiador de apps. Dos estados: la lista de apps instaladas y, al
/// elegir una, todo lo que se va a mandar a la papelera.
struct AppCleanerPage: View {
    @ObservedObject private var cleaner = AppCleaner.shared
    @State private var query = ""
    @State private var confirming = false

    var body: some View {
        Form {
            if let app = cleaner.selected {
                detail(app)
            } else {
                appList
            }
        }
        .onAppear { cleaner.loadApps() }
    }

    // MARK: - Lista de apps

    private var filtered: [InstalledApp] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return cleaner.apps }
        return cleaner.apps.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    @ViewBuilder
    private var appList: some View {
        orphanSection
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Buscar una app", "Search for an app"), text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text(L("Desinstalar una app", "Uninstall an app"))
        } footer: {
            Text(L("Elige una app y verás lo que deja por el sistema. Todo va a la papelera, así que siempre se puede recuperar.",
                   "Pick an app and you'll see what it leaves behind. Everything goes to the Trash, so it can always be recovered."))
            .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            if cleaner.loading && cleaner.apps.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Buscando apps…", "Looking for apps…")).foregroundStyle(.secondary)
                }
            } else if filtered.isEmpty {
                Text(L("Ninguna app con ese nombre.", "No app with that name."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filtered) { app in
                    Button {
                        cleaner.select(app)
                    } label: {
                        HStack(spacing: 10) {
                            icon(for: app.url, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name)
                                Text(app.version.map { "\(L("Versión", "Version")) \($0)" } ?? app.bundleID)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            Text(CacheCleaner.format(app.size))
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Restos de apps que ya no están

    @ViewBuilder
    private var orphanSection: some View {
        Section {
            if cleaner.scanningOrphans {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Buscando por la biblioteca…", "Searching your library…")).foregroundStyle(.secondary)
                }
            } else if cleaner.orphans.isEmpty {
                SettingRow(title: L("Restos de apps que ya no tienes", "Leftovers from apps you no longer have"),
                           subtitle: L("Cuando arrastras una app a la papelera, sus datos se quedan. Esto los busca.",
                                       "When you drag an app to the Trash its data stays behind. This finds it.")) {
                    Button(L("Buscar", "Search")) { cleaner.scanOrphans() }
                }
            } else {
                ForEach(cleaner.orphans) { orphan in
                    Toggle(isOn: Binding(
                        get: { cleaner.checkedOrphans.contains(orphan.bundleID) },
                        set: { on in
                            if on { cleaner.checkedOrphans.insert(orphan.bundleID) }
                            else { cleaner.checkedOrphans.remove(orphan.bundleID) }
                        })) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 5) {
                                    Text(orphan.name)
                                    // Se avisa antes de marcar, no después de fallar.
                                    if orphan.urls.allSatisfy({ $0.path.contains("/Library/Containers")
                                                                || $0.path.contains("/Library/Group Containers") }) {
                                        Text(L("solo desde el Finder", "Finder only"))
                                            .font(.caption2)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(.quaternary, in: Capsule())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(L("\(orphan.bundleID) · \(orphan.urls.count) elementos",
                                       "\(orphan.bundleID) · \(orphan.urls.count) items"))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 12)
                            // Mientras se mide, un guion: es más honesto que enseñar
                            // «0 bytes» en algo que todavía no se ha contado.
                            Text(orphan.size > 0 ? CacheCleaner.format(orphan.size)
                                                 : (cleaner.measuringOrphans ? "—" : CacheCleaner.format(0)))
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                if !cleaner.protectedPaths.isEmpty {
                    // Que no falle en silencio: se dice qué ha pasado y se ofrece la
                    // única salida que existe.
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("macOS no deja que ninguna app toque las carpetas de Contenedores, ni con Acceso total al disco: solo el Finder puede quitarlas. Estas \(cleaner.protectedPaths.count) se han quedado ahí.",
                               "macOS won't let any app touch Containers folders, not even with Full Disk Access: only Finder can remove them. These \(cleaner.protectedPaths.count) stayed put."))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(L("Mostrar en el Finder", "Show in Finder")) { cleaner.revealProtected() }
                            .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
                HStack {
                    Button(L("Buscar otra vez", "Search again")) { cleaner.scanOrphans() }
                    if cleaner.measuringOrphans {
                        ProgressView().controlSize(.small)
                        Text(L("Midiendo tamaños…", "Measuring sizes…"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        cleaner.trashCheckedOrphans()
                    } label: {
                        Text(L("Mover a la papelera · \(CacheCleaner.format(cleaner.checkedOrphanSize))",
                               "Move to Trash · \(CacheCleaner.format(cleaner.checkedOrphanSize))"))
                    }
                    .disabled(cleaner.checkedOrphans.isEmpty)
                }
            }
        } header: {
            Text(L("Restos de apps que ya no tienes", "Leftovers from apps you no longer have"))
        } footer: {
            if !cleaner.orphans.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Ninguno viene marcado, y con razón: algunos pueden ser de ayudantes de apps que sí tienes o de cosas instaladas fuera de la carpeta Aplicaciones. Mira el identificador antes de marcar.",
                           "None are ticked, and for good reason: some may belong to helpers of apps you do have, or to things installed outside your Applications folder. Check the identifier before ticking."))
                    // Que el aviso del sistema no pille por sorpresa: aparece al medir,
                    // no al buscar, y decir que no solo cuesta los tamaños.
                    Text(L("Para saber cuánto ocupan hay que leer dentro, y macOS pedirá permiso para acceder a los datos de otras apps. Si dices que no, la lista sigue estando; solo te quedas sin los tamaños.",
                           "Working out how much space they take means reading inside them, so macOS will ask for permission to access other apps' data. If you say no, the list still works — you just won't see the sizes."))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Detalle de una app

    @ViewBuilder
    private func detail(_ app: InstalledApp) -> some View {
        Section {
            HStack(spacing: 12) {
                icon(for: app.url, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.title3.weight(.semibold))
                    Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Volver", "Back")) { cleaner.clearSelection() }
            }
        }

        Section {
            row(title: L("La app", "The app"),
                subtitle: app.url.path,
                size: app.size,
                url: app.url,
                needsAdmin: false)
        } header: {
            Text(L("Se va a la papelera", "Going to the Trash"))
        }

        Section {
            if cleaner.scanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Buscando restos…", "Looking for leftovers…")).foregroundStyle(.secondary)
                }
            } else if cleaner.leftovers.isEmpty {
                Text(L("No ha dejado nada por el sistema.", "It left nothing behind."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(cleaner.leftovers) { leftover in
                    row(title: leftover.place,
                        subtitle: friendlyPath(leftover.url),
                        size: leftover.size,
                        url: leftover.url,
                        needsAdmin: leftover.needsAdmin)
                }
            }
        } header: {
            Text(L("Restos", "Leftovers"))
        } footer: {
            if cleaner.leftovers.contains(where: \.needsAdmin) {
                Text(L("Los que están fuera de tu carpeta de usuario necesitan contraseña de administrador; van desmarcados.",
                       "The ones outside your home folder need an administrator password, so they start unticked."))
                .font(.caption).foregroundStyle(.secondary)
            }
        }

        Section {
            HStack {
                if let result = cleaner.lastResult {
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    confirming = true
                } label: {
                    Text(L("Mover a la papelera · \(cleaner.checkedSizeText)",
                           "Move to Trash · \(cleaner.checkedSizeText)"))
                }
                .disabled(cleaner.checked.isEmpty)
                .confirmationDialog(L("¿Mandar a la papelera \(cleaner.checked.count) elementos de \(app.name)?",
                                      "Move \(cleaner.checked.count) items belonging to \(app.name) to the Trash?"),
                                    isPresented: $confirming, titleVisibility: .visible) {
                    Button(L("Mover a la papelera", "Move to Trash"), role: .destructive) {
                        cleaner.trashChecked()
                    }
                    Button(L("Cancelar", "Cancel"), role: .cancel) {}
                } message: {
                    Text(L("Nada se borra del todo: puedes recuperarlo desde la papelera.",
                           "Nothing is deleted for good: you can put it back from the Trash."))
                }
            }
        }
    }

    /// Una fila con su casilla, lo que ocupa y dónde está.
    private func row(title: String, subtitle: String, size: Int64, url: URL, needsAdmin: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { cleaner.checked.contains(url) },
            set: { on in
                if on { cleaner.checked.insert(url) } else { cleaner.checked.remove(url) }
            })) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(title)
                        if needsAdmin {
                            Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 12)
                Text(CacheCleaner.format(size)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .toggleStyle(.checkbox)
    }

    /// `/Users/<usuario>/Library/Caches/x` → `~/Library/Caches/x`
    private func friendlyPath(_ url: URL) -> String {
        let home = NSHomeDirectory()
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    private func icon(for url: URL, size: CGFloat) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: size, height: size)
    }
}
