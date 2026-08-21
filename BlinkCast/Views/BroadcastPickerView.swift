import SwiftUI
#if os(iOS)
import ReplayKit
import UIKit

struct BroadcastPickerView: UIViewRepresentable {
    let preferredExtension: String

    func makeUIView(context: Context) -> BroadcastPickerContainerView {
        NSLog("BlinkCast picker makeUIView extension=\(preferredExtension) bundle=\(Bundle.main.bundleIdentifier ?? "unknown")")
        let view = BroadcastPickerContainerView()
        view.configure(preferredExtension: preferredExtension)
        return view
    }

    func updateUIView(
        _ uiView: BroadcastPickerContainerView,
        context: Context
    ) {
        NSLog("BlinkCast picker updateUIView extension=\(preferredExtension)")
        uiView.configure(preferredExtension: preferredExtension)
    }
}

final class BroadcastPickerContainerView: UIView {
    private let picker = RPSystemBroadcastPickerView(frame: .zero)
    private let launchButton = UIButton(type: .system)
    private var configuredExtension = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        NSLog("BlinkCast picker container init frame=\(frame)")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAutoStart),
            name: Notification.Name("BlinkCast.StartScreenShare"),
            object: nil
        )

        picker.showsMicrophoneButton = false
        picker.alpha = 0.02
        picker.isUserInteractionEnabled = false
        addSubview(picker)

        launchButton.setImage(
            UIImage(systemName: "dot.radiowaves.left.and.right"),
            for: .normal
        )
        launchButton.tintColor = .systemBlue
        launchButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        launchButton.layer.cornerRadius = 12
        launchButton.accessibilityLabel = "Start Screen Share"
        launchButton.addTarget(
            self,
            action: #selector(handleTap),
            for: .touchUpInside
        )
        addSubview(launchButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func configure(preferredExtension: String) {
        NSLog("BlinkCast picker configure requested=\(preferredExtension) current=\(configuredExtension)")
        if configuredExtension != preferredExtension {
            configuredExtension = preferredExtension
            picker.preferredExtension = preferredExtension
            NSLog("BlinkCast creating ReplayKit broadcast picker for \(preferredExtension)")
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        picker.frame = bounds
        launchButton.frame = bounds
        NSLog("BlinkCast picker layout bounds=\(bounds) pickerSubviews=\(picker.subviews.count)")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        NSLog("BlinkCast picker didMoveToWindow window=\(window != nil) hidden=\(isHidden) alpha=\(alpha) userInteraction=\(isUserInteractionEnabled)")
    }

    @objc private func handleTap() {
        NSLog("BlinkCast picker tap received appState=\(UIApplication.shared.applicationState.rawValue) extension=\(configuredExtension)")
        NSLog("BlinkCast picker hierarchy count=\(picker.subviews.count) types=\(picker.subviews.map { String(describing: type(of: $0)) })")

        guard let button = picker.subviews
            .compactMap({ $0 as? UIButton })
            .first else {
            NSLog("BlinkCast picker ERROR internal ReplayKit UIButton not found")
            return
        }

        NSLog("BlinkCast picker internal button found enabled=\(button.isEnabled) hidden=\(button.isHidden) frame=\(button.frame)")
        BlinkCastExtensionDiagnosticsMonitor.shared.beginAwaitingExtensionLogs()
        button.sendActions(for: .touchUpInside)
        NSLog("BlinkCast picker requested ReplayKit broadcast sheet")
    }

    @objc private func handleAutoStart() {
        NSLog("BlinkCast picker auto-start requested")
        handleTap()
    }
}
#endif
