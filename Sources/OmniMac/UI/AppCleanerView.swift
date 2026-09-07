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

    /// `/Users/sergi/Library/Caches/x` → `~/Library/Caches/x`
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
