import Foundation
import SwiftUI
import UIKit

// MARK: - 轻量 Markdown 解析（iOS 14 没有 AttributedString 的 Markdown 支持）

struct MarkdownBlock: Identifiable {
    enum Kind {
        case paragraph(String)
        case heading(Int, String)
        case bullet(String)
        case numbered(Int, String)
        case quote(String)
        case code(String?, String)
        case divider
    }

    let id: Int
    let kind: Kind
}

enum MarkdownParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var language: String?
        var inCode = false

        let lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(MarkdownBlock(id: blocks.count, kind: .paragraph(paragraph.joined(separator: "\n"))))
            paragraph.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(MarkdownBlock(id: blocks.count, kind: .code(language, codeLines.joined(separator: "\n"))))
                    codeLines.removeAll()
                    language = nil
                    inCode = false
                } else {
                    flushParagraph()
                    let tag = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    language = tag.isEmpty ? nil : tag
                    inCode = true
                }
                continue
            }

            if inCode {
                codeLines.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(MarkdownBlock(id: blocks.count, kind: .divider))
                continue
            }

            if trimmed.hasPrefix("#") {
                var level = 0
                for character in trimmed {
                    if character == "#" { level += 1 } else { break }
                }
                if level > 0 && level <= 6 {
                    flushParagraph()
                    let title = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                    blocks.append(MarkdownBlock(id: blocks.count, kind: .heading(min(level, 3), title)))
                    continue
                }
            }

            if trimmed.hasPrefix("> ") {
                flushParagraph()
                blocks.append(MarkdownBlock(id: blocks.count, kind: .quote(String(trimmed.dropFirst(2)))))
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                blocks.append(MarkdownBlock(id: blocks.count, kind: .bullet(String(trimmed.dropFirst(2)))))
                continue
            }

            if let match = numberedPrefix(trimmed) {
                flushParagraph()
                blocks.append(MarkdownBlock(id: blocks.count, kind: .numbered(match.0, match.1)))
                continue
            }

            paragraph.append(line)
        }

        if inCode && !codeLines.isEmpty {
            blocks.append(MarkdownBlock(id: blocks.count, kind: .code(language, codeLines.joined(separator: "\n"))))
        }
        flushParagraph()
        return blocks
    }

    private static func numberedPrefix(_ line: String) -> (Int, String)? {
        var digits = ""
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            digits.append(line[index])
            index = line.index(after: index)
        }
        guard !digits.isEmpty, index < line.endIndex else { return nil }
        let rest = line[index...]
        guard rest.hasPrefix(".") || rest.hasPrefix("、") else { return nil }
        let body = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty, let number = Int(digits) else { return nil }
        return (number, body)
    }
}

enum MarkdownInline {
    static func render(_ text: String) -> Text {
        let pattern = "(`[^`]+`|\\*\\*[^*]+\\*\\*|\\*[^*\\n]+\\*|_[^_\\n]+_|\\[[^\\]]+\\]\\([^)]+\\))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return Text(text)
        }

        let source = text as NSString
        var output = Text("")
        var cursor = 0

        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            if match.range.location > cursor {
                let plain = source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                output = output + Text(plain)
            }
            let token = source.substring(with: match.range)
            output = output + renderToken(token)
            cursor = match.range.location + match.range.length
        }

        if cursor < source.length {
            output = output + Text(source.substring(from: cursor))
        }
        return output
    }

    private static func renderToken(_ token: String) -> Text {
        if token.hasPrefix("`") && token.hasSuffix("`") && token.count > 2 {
            let inner = String(token.dropFirst().dropLast())
            return Text(inner)
                .font(.system(size: 14.5, design: .monospaced))
                .foregroundColor(Theme.accent)
        }
        if token.hasPrefix("**") && token.hasSuffix("**") && token.count > 4 {
            return Text(String(token.dropFirst(2).dropLast(2))).bold()
        }
        if token.hasPrefix("*") && token.hasSuffix("*") && token.count > 2 {
            return Text(String(token.dropFirst().dropLast())).italic()
        }
        if token.hasPrefix("_") && token.hasSuffix("_") && token.count > 2 {
            return Text(String(token.dropFirst().dropLast())).italic()
        }
        if token.hasPrefix("[") {
            if let closing = token.range(of: "](") {
                let label = String(token[token.index(after: token.startIndex)..<closing.lowerBound])
                return Text(label).foregroundColor(Theme.accent).underline()
            }
        }
        return Text(token)
    }
}

// MARK: - 渲染

struct MarkdownView: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    private var blocks: [MarkdownBlock] {
        MarkdownParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .paragraph(let content):
            MarkdownInline.render(content)
                .font(.system(size: 16))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let level, let content):
            MarkdownInline.render(content)
                .font(.system(size: level <= 1 ? 20 : (level == 2 ? 18 : 16), weight: .semibold))
                .padding(.top, 2)

        case .bullet(let content):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.accent)
                    .padding(.top, 1)
                MarkdownInline.render(content)
                    .font(.system(size: 16))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .numbered(let number, let content):
            HStack(alignment: .top, spacing: 8) {
                Text("\(number).")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.accent)
                    .padding(.top, 3)
                MarkdownInline.render(content)
                    .font(.system(size: 16))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .quote(let content):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.accent.opacity(0.55))
                    .frame(width: 3)
                MarkdownInline.render(content)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.subtleText(scheme))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .code(let language, let content):
            CodeBlockView(code: content, language: language)

        case .divider:
            Divider().padding(.vertical, 2)
        }
    }
}

struct CodeBlockView: View {
    let code: String
    let language: String?

    @State private var copied = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text((language ?? "code").uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.subtleText(scheme))
                    .lineLimit(1)
                Spacer()
                Button(action: copy) {
                    Text(copied ? "已复制" : "复制")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(copied ? Theme.success : Theme.subtleText(scheme))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.4)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .padding(12)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .background(Theme.codeBackground(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.border(scheme), lineWidth: 1)
        )
    }

    private func copy() {
        UIPasteboard.general.string = code
        Haptics.light()
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.15)) { copied = false }
        }
    }
}
