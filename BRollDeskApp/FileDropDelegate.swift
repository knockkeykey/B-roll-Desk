import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum FileURLDropLoader {
    static func loadURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let resultBuffer = FileURLResultBuffer(count: providers.count)

        for (index, provider) in providers.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                resultBuffer.store(Self.fileURL(from: item), at: index)
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(resultBuffer.urls)
        }
    }

    static func urls(from providers: [NSItemProvider]) async -> [URL] {
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
                continuation.resume(returning: Self.fileURL(from: item))
            }
        }
    }

    private static func fileURL(from item: Any?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let url = item as? NSURL {
            return url as URL
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        return nil
    }
}

private final class FileURLResultBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URL?]

    init(count: Int) {
        values = Array(repeating: nil, count: count)
    }

    func store(_ url: URL?, at index: Int) {
        lock.lock()
        values[index] = url
        lock.unlock()
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return values.compactMap { $0 }
    }
}

final class DropFeedbackModel: ObservableObject {
    @Published var isFileDragActive = false
}

final class FolderDragFeedbackModel: ObservableObject {
    @Published private(set) var isDirectoryDragActive = false

    private var inspectionGeneration = UUID()

    func inspect(_ providers: [NSItemProvider]) {
        let generation = UUID()
        inspectionGeneration = generation
        isDirectoryDragActive = false

        Task { @MainActor in
            for provider in providers {
                guard let url = await Self.fileURL(from: provider) else { continue }
                let didStartAccess = url.startAccessingSecurityScopedResource()
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
                guard isDirectory else { continue }
                guard inspectionGeneration == generation else { return }
                isDirectoryDragActive = true
                return
            }
        }
    }

    func endInspection() {
        inspectionGeneration = UUID()
        isDirectoryDragActive = false
    }

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let url = item as? NSURL {
                    continuation.resume(returning: url as URL)
                } else if let data = item as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

final class AnchorDropState: ObservableObject {
    @Published var isActive = false
}

struct FileDropDelegate: DropDelegate {
    let rowID: String
    let model: AppModel
    let feedback: DropFeedbackModel
    let rowState: AnchorDropState
    var onBindingStarted: () -> Void = {}
    var onBindingFinished: () -> Void = {}

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

        model.bindingRowIDs.insert(rowID)
        onBindingStarted()
        Task { @MainActor in
            defer {
                model.bindingRowIDs.remove(rowID)
                onBindingFinished()
            }
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

struct WholeWindowDirectoryDropDelegate: DropDelegate {
    let feedback: FolderDragFeedbackModel

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL])
    }

    func dropEntered(info: DropInfo) {
        feedback.inspect(info.itemProviders(for: [UTType.fileURL]))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .cancel)
    }

    func dropExited(info: DropInfo) {
        feedback.endInspection()
    }

    func performDrop(info: DropInfo) -> Bool {
        feedback.endInspection()
        return false
    }
}

struct DirectoryDropTargetModifier: ViewModifier {
    let onDrop: (URL) -> Void

    @EnvironmentObject private var folderDragFeedback: FolderDragFeedbackModel
    @State private var isDropTarget = false

    func body(content: Content) -> some View {
        let shouldPulse = isDropTarget || folderDragFeedback.isDirectoryDragActive

        content
            .overlay {
                if shouldPulse {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        let phase = (sin(context.date.timeIntervalSinceReferenceDate * 2.4) + 1) / 2
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.accentColor.opacity(0.035 + phase * 0.055))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(
                                        Color.accentColor.opacity(0.48 + phase * 0.42),
                                        style: StrokeStyle(lineWidth: 1.2 + phase * 0.6, dash: [6, 4])
                                    )
                            }
                            .scaleEffect(0.992 + phase * 0.016)
                            .allowsHitTesting(false)
                    }
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTarget, perform: acceptDrop)
            .accessibilityHint(shouldPulse ? "请将文件夹放到此处" : "也可以从 Finder 拖入文件夹")
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }

        FileURLDropLoader.loadURLs(from: fileProviders) { urls in
            for url in urls {
                let didStartAccess = url.startAccessingSecurityScopedResource()
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
                guard isDirectory else { continue }
                onDrop(url)
                return
            }
        }
        return true
    }
}
