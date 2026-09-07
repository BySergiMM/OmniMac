import AppIntents
import SwiftUI
import WidgetKit

/// Nombre de la notificación que despierta a OmniMac. Los controles viven en un
/// proceso aparte (así lo exige el sistema), así que le hablan a la app por
/// notificaciones distribuidas: no hacen falta permisos ni grupos de apps.
enum ControlBridge {
    static let toggleKeepAwake = "com.seergiii.omnimac.control.keepAwake"
}

@available(macOS 15.0, *)
struct KeepAwakeIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Mantener despierto"
    @Parameter(title: "Activado") var value: Bool

    func perform() async throws -> some IntentResult {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(ControlBridge.toggleKeepAwake),
            object: value ? "1" : "0",
            userInfo: nil,
            deliverImmediately: true)
        return .result()
    }
}

@available(macOS 15.0, *)
struct KeepAwakeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.seergiii.omnimac.keepAwake") {
            ControlWidgetToggle("Mantener despierto", isOn: false, action: KeepAwakeIntent()) { isOn in
                Label(isOn ? "Activado" : "Desactivado", systemImage: "cup.and.saucer.fill")
            }
        }
    }
}

@available(macOS 15.0, *)
@main
struct OmniMacControls: WidgetBundle {
    var body: some Widget { KeepAwakeControl() }
}
