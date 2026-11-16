import SwiftUI
import UIKit

/// Renders a share card the one way every share does (the Board's widget styles, a record, a
/// Challenge): opaque, at `BoardShareFormat.renderScale`, and for the share sheet as a PNG in a
/// temporary folder of its own.
@MainActor
enum ShareImageRenderer {
    static func image(_ card: some View) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = BoardShareFormat.renderScale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// `card` as a PNG named `name` in the temporary folder `folder`, replacing an earlier one of
    /// the same name.
    static func file(_ card: some View, folder: String, name: String) throws -> URL {
        guard let data = image(card)?.pngData() else { throw CocoaError(.fileWriteUnknown) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
