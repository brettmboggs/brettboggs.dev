import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Share › Ladle" from Safari. Takes the page's address, drops it in the App
/// Group inbox, shows a one-line confirmation and gets out of the way. The
/// app does the reading the next time it is opened.
/// No `@objc(...)` rename: Info.plist names the class as
/// `$(PRODUCT_MODULE_NAME).ShareViewController`, which is its default runtime
/// name, and a rename would stop the system finding it.
final class ShareViewController: UIViewController {
    private let groupID = "group.dev.brettboggs.ladle"
    private var host: UIHostingController<ShareConfirmation>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        show(message: "Saving…", done: false)
        collectURL { [weak self] url in
            DispatchQueue.main.async {
                guard let self else { return }
                if let url, self.store(url) {
                    self.show(message: "Saved to Ladle", done: true)
                } else {
                    self.show(message: "That did not look like a web page.", done: true)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    self.extensionContext?.completeRequest(returningItems: nil)
                }
            }
        }
    }

    private func show(message: String, done: Bool) {
        let content = ShareConfirmation(message: message, done: done)
        if let host {
            host.rootView = content
            return
        }
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = .clear
        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        controller.didMove(toParent: self)
        host = controller
    }

    /// The first web address among the shared items.
    private func collectURL(_ completion: @escaping (URL?) -> Void) {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []
        guard !providers.isEmpty else { completion(nil); return }

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    completion(url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    completion(url)
                } else {
                    completion(nil)
                }
            }
            return
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                let text = (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
                   let match = detector.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
                   let url = match.url {
                    completion(url)
                } else {
                    completion(nil)
                }
            }
            return
        }
        completion(nil)
    }

    private func store(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { return false }
        let inbox = container.appendingPathComponent("Inbox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let payload: [String: Any] = ["url": url.absoluteString, "date": ISO8601DateFormatter().string(from: Date())]
            let data = try JSONSerialization.data(withJSONObject: payload)
            try data.write(to: inbox.appendingPathComponent(UUID().uuidString + ".json"), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

struct ShareConfirmation: View {
    let message: String
    let done: Bool

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 22, weight: .medium))
                VStack(alignment: .leading, spacing: 2) {
                    Text(message)
                        .font(.system(size: 16, weight: .semibold))
                    if done && message.hasPrefix("Saved") {
                        Text("Open Ladle to check it and save it.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .systemBackground)))
            .padding(20)
        }
    }
}
