#if os(macOS)

import SwiftUI
import AppKit

struct MacWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            configureWindow(from: view)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(from: nsView)
        }
    }

    private func configureWindow(from view: NSView) {
        guard let window = view.window else {
            return
        }

        window.styleMask.insert(.fullSizeContentView)

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none

        window.isOpaque = false
        window.backgroundColor = .clear

        window.isMovable = true
        window.isMovableByWindowBackground = true

        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false

        if let toolbar = window.toolbar {
            toolbar.isVisible = false
            toolbar.showsBaselineSeparator = false
        }
    }
}

#endif