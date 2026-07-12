import Foundation

// MARK: - Attachment Data Model

struct AttachmentData: Identifiable, Equatable {
    let id = UUID()
    let data: Data
    let fileName: String
    let mimeType: String
    var isImage: Bool { mimeType.hasPrefix("image/") }

    var fileExtension: String {
        (fileName as NSString).pathExtension
    }

    var fileIcon: String {
        let ext = fileExtension.lowercased()
        switch ext {
        case "pdf": return "doc.text.fill"
        case "txt", "md", "log": return "doc.text"
        case "json", "xml", "yaml", "yml": return "curlybraces"
        case "swift", "py", "js", "ts", "go", "rs", "java", "c", "cpp": return "chevron.left.forwardslash.chevron.right"
        case "zip", "tar", "gz", "rar": return "archivebox.fill"
        case "csv", "xls", "xlsx": return "tablecells.fill"
        case "doc", "docx": return "doc.richtext.fill"
        default: return "doc.fill"
        }
    }
}
