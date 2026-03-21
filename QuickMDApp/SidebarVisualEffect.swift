import AppKit
import SwiftUI

/// macOS sidebar vibrancy (“Behind Window”) with a light Stitch tint in light mode.
struct SidebarChromeBackground: NSViewRepresentable {
    var colorScheme: ColorScheme

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true

        let effect = NSVisualEffectView()
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]

        let tint = NSView()
        tint.wantsLayer = true
        tint.autoresizingMask = [.width, .height]

        container.addSubview(effect)
        container.addSubview(tint)
        context.coordinator.effectView = effect
        context.coordinator.tintView = tint
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let effect = context.coordinator.effectView,
              let tint = context.coordinator.tintView else { return }
        effect.frame = nsView.bounds
        tint.frame = nsView.bounds
        if colorScheme == .light {
            tint.layer?.backgroundColor = NSColor(QuickMDDesignTokens.surfaceContainerLow(for: .light)).withAlphaComponent(0.45).cgColor
        } else {
            tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var effectView: NSVisualEffectView?
        weak var tintView: NSView?
    }
}
