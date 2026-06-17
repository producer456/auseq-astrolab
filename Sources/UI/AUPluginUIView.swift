import SwiftUI
import AVFoundation

/// Embeds an AUv3's own view controller (its native plugin UI).
struct AUPluginUIView: UIViewControllerRepresentable {
    let au: AUAudioUnit

    func makeUIViewController(context: Context) -> UIViewController {
        let container = ContainerController()
        au.requestViewController { vc in
            DispatchQueue.main.async {
                container.embed(vc)
            }
        }
        return container
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class ContainerController: UIViewController {
        private var pluginVC: UIViewController?

        func embed(_ vc: UIViewController?) {
            guard let vc else {
                let label = UILabel()
                label.text = "This plugin has no custom UI."
                label.textColor = .secondaryLabel
                label.textAlignment = .center
                label.frame = view.bounds
                label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.addSubview(label)
                return
            }
            addChild(vc)
            vc.view.frame = view.bounds
            vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(vc.view)
            vc.didMove(toParent: self)
            pluginVC = vc
        }
    }
}
