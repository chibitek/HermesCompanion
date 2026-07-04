import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI wrapper around UIDocumentPickerViewController for selecting
/// arbitrary files (PDF, text, code, etc.) from the Files app.
///
/// Returns the selected file data, file name, and inferred MIME type
/// via a completion callback.
struct FilePickerView: UIViewControllerRepresentable {
    let onPick: (Data, String, String) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Support a broad range of content types
        let supportedTypes: [UTType] = [
            .pdf,
            .plainText,
            .json,
            .xml,
            .yaml,
            .sourceCode,
            .text,
            .commaSeparatedText,
            .rtf,
            .zip,
            .data,
            .item
        ]

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (Data, String, String) -> Void

        init(onPick: @escaping (Data, String, String) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            for url in urls {
                // Security-scoped resource access for files outside the app's sandbox
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                guard let data = try? Data(contentsOf: url) else { continue }
                let fileName = url.lastPathComponent
                let mimeType = MimeTypeResolver.resolve(for: url)
                onPick(data, fileName, mimeType)
            }
        }
    }
}

/// Resolves a file URL to its MIME type based on extension and UTType.
enum MimeTypeResolver {
    static func resolve(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()

        // Try UTType first
        if let utType = UTType(filenameExtension: ext),
           let mimeType = utType.preferredMIMEType {
            return mimeType
        }

        // Fallback mapping for common types
        switch ext {
        // Documents
        case "pdf": return "application/pdf"
        case "txt", "log": return "text/plain"
        case "md", "markdown": return "text/markdown"
        case "rtf": return "application/rtf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

        // Code
        case "swift": return "text/x-swift"
        case "py": return "text/x-python"
        case "js", "mjs": return "text/javascript"
        case "ts": return "text/typescript"
        case "go": return "text/x-go"
        case "rs": return "text/x-rust"
        case "java": return "text/x-java"
        case "c", "h": return "text/x-c"
        case "cpp", "hpp", "cc": return "text/x-c++"
        case "rb": return "text/x-ruby"
        case "sh", "bash": return "text/x-shellscript"
        case "sql": return "application/sql"
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "xml": return "application/xml"

        // Data
        case "json": return "application/json"
        case "yaml", "yml": return "application/x-yaml"
        case "toml": return "application/toml"
        case "csv": return "text/csv"
        case "tsv": return "text/tab-separated-values"
        case "ini", "cfg", "conf": return "text/plain"

        // Archives
        case "zip": return "application/zip"
        case "tar": return "application/x-tar"
        case "gz", "gzip": return "application/gzip"

        // Images (fallback if UTType fails)
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"

        // Audio/Video
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"

        default: return "application/octet-stream"
        }
    }

    /// Determine if a MIME type represents a text-based file that can be
    /// sent as inline text content rather than base64.
    static func isTextType(_ mimeType: String) -> Bool {
        mimeType.hasPrefix("text/") ||
        mimeType == "application/json" ||
        mimeType == "application/xml" ||
        mimeType == "application/x-yaml" ||
        mimeType == "application/toml" ||
        mimeType == "application/sql"
    }
}
