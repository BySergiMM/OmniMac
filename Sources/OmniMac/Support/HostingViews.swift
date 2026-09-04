import AppKit
import SwiftUI

/// Hosting view cuyo primer clic cuenta aunque la ventana no sea "key": en los
/// paneles sin activación (selector ⌘Tab, portapapeles) el primer clic no se
/// pierde en "enfocar" la ventana.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    required init(rootView: Content) { super.init(rootView: rootView) }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no soportado") }
}
