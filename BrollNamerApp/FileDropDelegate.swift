import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class DropFeedbackModel: ObservableObject {
    @Published var isFileDragActive = false
}

final class AnchorDropState: ObservableObject {
    @Published var isActive = false
}

struct FileDropDelegate: DropDelegate {
    let rowID: String
    let model: AppModel
    let feedback: DropFeedbackModel
    let rowState: AnchorDropState

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL])
    }

    func dropEntered(info: DropInfo) {
        guard info.hasItemsConforming(to: [UTType.fileURL]) else { return }
        feedback.isFileDragActive = true
        rowState.isActive = true
    }

    func dropExited(info: DropInfo) {
        rowState.isActive = false
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.fileURL])
        guard !providers.isEmpty else { return false }

        feedback.isFileDragActive = false
        rowState.isActive = false

        Task { @MainActor in
            let urls = await Self.urls(from: providers)
            await model.attach(urls: urls, to: rowID)
        }
        return true
    }

    private static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await url(from: provider) {
                urls.append(url)
            }
        }
        return urls
    }

    private static func url(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }
                if let url = item as? NSURL {
                    continuation.resume(returning: url as URL)
                    return
                }
                if let data = item as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }
}

struct AnchorListDropDelegate: DropDelegate {
    let feedback: DropFeedbackModel

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL])
    }

    func dropEntered(info: DropInfo) {
        guard info.hasItemsConforming(to: [UTType.fileURL]) else { return }
        feedback.isFileDragActive = true
    }

    func dropExited(info: DropInfo) {
        feedback.isFileDragActive = false
    }

    func performDrop(info: DropInfo) -> Bool {
        feedback.isFileDragActive = false
        return false
    }
}
