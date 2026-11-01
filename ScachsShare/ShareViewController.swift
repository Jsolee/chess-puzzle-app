import UIKit
import UniformTypeIdentifiers

/// Takes a game link, a PGN or a picture of a board, leaves it for the app, and gets out of the way.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.059, green: 0.227, blue: 0.2, alpha: 1)
        let label = UILabel()
        label.text = String(localized: "Afegit a Scachs. Obre l'app per veure-ho.")
        label.textColor = UIColor(red: 0.965, green: 0.945, blue: 0.902, alpha: 1)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .headline)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
        ])
        Task { await take() }
    }

    private func take() async {
        let attachments = (extensionContext?.inputItems as? [NSExtensionItem])?.flatMap { $0.attachments ?? [] } ?? []
        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
               let data = try? await provider.loadDataRepresentation(for: .image) {
                Inbox.put(image: data)
            } else if provider.canLoadObject(ofClass: URL.self), let url = try? await provider.loadObject(ofClass: URL.self) {
                Inbox.put(text: url.absoluteString)
            } else if provider.canLoadObject(ofClass: String.self), let text = try? await provider.loadObject(ofClass: String.self) {
                Inbox.put(text: text)
            }
        }
        try? await Task.sleep(for: .milliseconds(900))
        extensionContext?.completeRequest(returningItems: nil)
    }
}

private extension NSItemProvider {
    func loadDataRepresentation(for type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let data { continuation.resume(returning: data) } else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
    }

    func loadObject<T: _ObjectiveCBridgeable>(ofClass: T.Type) async throws -> T where T._ObjectiveCType: NSItemProviderReading {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadObject(ofClass: T.self) { value, error in
                if let value { continuation.resume(returning: value) } else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
    }
}
