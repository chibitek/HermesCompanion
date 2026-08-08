import Foundation

/// Minimal block-level markdown splitter for chat messages.
///
/// iOS's `AttributedString(markdown:)` only handles inline syntax, so fenced
/// code blocks, headings, and lists render as literal text. This splits a
/// message into blocks; inline rendering inside text blocks stays AttributedString.
///
/// ponytail: intentionally naive — no nested lists, no tables, no setext
/// headings, inline `code` only via AttributedString. Add tables/nesting when
/// Erick's chat content actually needs them.
enum MarkdownBlocks {
    enum Block: Equatable {
        /// Plain paragraph (or heading line with `#`s stripped). May contain inline markdown.
        case text(String)
        /// Bullet/numbered list. Lines carry no leading marker; each is one item.
        case list([String], ordered: Bool)
        /// Fenced code block with optional language tag. Content is verbatim.
        case code(language: String?, code: String)
    }

    static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var textBuffer: [String] = []
        var listBuffer: [String] = []
        var listOrdered = false

        func flushText() {
            let joined = textBuffer.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.text(joined))
            }
            textBuffer = []
        }

        func flushList() {
            if !listBuffer.isEmpty {
                blocks.append(.list(listBuffer, ordered: listOrdered))
                listBuffer = []
            }
        }

        var lines = markdown.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block: ```lang ... ```
            if trimmed.hasPrefix("```") {
                flushText()
                flushList()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                // ponytail: unclosed fence (mid-stream) renders as code with what we have.
                blocks.append(.code(language: lang.isEmpty ? nil : lang, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Heading: strip #s, render as plain text (inline markdown still applies).
            if let heading = stripHeading(trimmed) {
                flushList()
                textBuffer.append(heading)
                i += 1
                continue
            }

            // List item: "- ", "* ", "+ ", "1."/"1)"
            if let (item, ordered) = stripListMarker(trimmed) {
                flushText()
                if listBuffer.isEmpty || listOrdered == ordered {
                    listOrdered = ordered
                    listBuffer.append(item)
                } else {
                    flushList()
                    listOrdered = ordered
                    listBuffer.append(item)
                }
                i += 1
                continue
            }

            // Blank line terminates the current block.
            if trimmed.isEmpty {
                flushText()
                flushList()
                i += 1
                continue
            }

            flushList()
            textBuffer.append(line)
            i += 1
        }
        flushText()
        flushList()
        return blocks
    }

    private static func stripHeading(_ line: String) -> String? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), hashes < line.count else { return nil }
        let idx = line.index(line.startIndex, offsetBy: hashes)
        guard line[idx] == " " else { return nil }
        return String(line[line.index(after: idx)...])
    }

    /// Returns (item text, isOrdered) or nil if the line isn't a list item.
    private static func stripListMarker(_ line: String) -> (String, Bool)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return (String(line.dropFirst(2)), false)
        }
        // Ordered: digits then . or ) then space. Cap digits at 9 to avoid
        // eating "12:30" style timestamps (needs a trailing space anyway).
        var digits = 0
        for ch in line {
            if ch.isNumber { digits += 1 } else { break }
        }
        guard digits > 0, digits <= 9, digits + 1 < line.count else { return nil }
        let afterDigits = line.index(line.startIndex, offsetBy: digits)
        guard line[afterDigits] == "." || line[afterDigits] == ")" else { return nil }
        let rest = line[line.index(after: afterDigits)...]
        guard rest.hasPrefix(" ") else { return nil }
        return (String(rest.dropFirst()), true)
    }

    // MARK: - Self-check

    static func runChecks() {
        let md = """
        # Title

        Hello **world**.

        - alpha
        - beta

        ```swift
        let x = 1 // ```
        ```

        1. one
        2. two

        12:30 stays text
        """
        let blocks = parse(md)
        assert(blocks.count == 6, "expected 6 blocks, got \(blocks.count): \(blocks)")
        guard case .text(let t0) = blocks[0], t0 == "Title" else { fatalError("heading strip failed") }
        guard case .text(let t1) = blocks[1], t1 == "Hello **world**." else { fatalError("para failed") }
        guard case .list(let items, false) = blocks[2], items == ["alpha", "beta"] else { fatalError("unordered list failed") }
        guard case .code(let lang, let code) = blocks[3], lang == "swift", code == "let x = 1 // ```" else { fatalError("code block failed") }
        guard case .list(let oitems, true) = blocks[4], oitems == ["one", "two"] else { fatalError("ordered list failed") }
        guard case .text(let t5) = blocks[5], t5.contains("12:30") else { fatalError("timestamp misparsed as list") }
    }
}
