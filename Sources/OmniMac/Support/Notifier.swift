import AppKit
import UserNotifications

/// Notificaciones locales (temporizador, fin del café, avisos de Rendimiento…).
enum Notifier {
    /// Con una ventana de OmniMac delante (Ajustes, por ejemplo), macOS no enseña los
    /// avisos de OmniMac salvo que la app lo pida: el «Enviar un aviso de prueba» de
    /// Ajustes no se veía nunca. Se pone al arrancar.
    static func install() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().delegate = Presenter.shared
    }

    private final class Presenter: NSObject, UNUserNotificationCenterDelegate {
        static let shared = Presenter()

        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .list, .sound])
        }
    }

    static func post(title: String, body: String, identifier: String = UUID().uuidString) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        }
    }

    // MARK: - Permiso

    enum Permission: Equatable {
        /// Aún no se ha preguntado: macOS enseñará su cuadro al pedirlo.
        case notAsked
        case allowed
        /// Dicho que no (o quitado en Ajustes). macOS ya no deja volver a preguntar:
        /// solo queda llevar a Ajustes del Sistema.
        case denied
    }

    static func permission() async -> Permission {
        // Sin identificador de paquete (el binario suelto de las pruebas) la API aborta.
        guard Bundle.main.bundleIdentifier != nil else { return .denied }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notAsked
        case .denied: return .denied
        default: return .allowed
        }
    }

    /// Pide el permiso **solo si aún no se ha preguntado**: así el aviso de macOS sale
    /// cuando el usuario quiere avisos, y no a ciegas cuando el primero ya ha llegado.
    @discardableResult
    static func requestIfNeeded() async -> Permission {
        let current = await permission()
        guard current == .notAsked else { return current }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        return granted ? .allowed : .denied
    }

    /// Ajustes del Sistema › Notificaciones, en el apartado de OmniMac.
    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? "com.seergiii.omnimac"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }
}
