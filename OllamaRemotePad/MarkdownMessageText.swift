import SwiftUI
import UIKit

struct MarkdownMessageText: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(parse(content).enumerated()), id: \.offset) { _, part in
                switch part {
                case .markdown(let text):
                    if let markdown = try? AttributedString(
                        markdown: text,
                        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
                    ) {
                        Text(markdown)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code)
                }
            }
        }
    }

    private func parse(_ text: String) -> [MessagePart] {
        var result: [MessagePart] = []
        let lines = text.components(separatedBy: .newlines)
        var buffer: [String] = []
        var inCodeBlock = false
        var codeLanguage = ""

        func flushMarkdown() {
            let markdown = buffer.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !markdown.isEmpty {
                result.append(.markdown(markdown))
            }
            buffer.removeAll(keepingCapacity: true)
        }

        func flushCode() {
            let code = buffer.joined(separator: "\n")
            result.append(.code(language: codeLanguage, code: code))
            buffer.removeAll(keepingCapacity: true)
            codeLanguage = ""
        }

        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    flushCode()
                } else {
                    flushMarkdown()
                    codeLanguage = String(line.dropFirst(3))
                }
                inCodeBlock.toggle()
            } else {
                buffer.append(line)
            }
        }

        if inCodeBlock {
            flushCode()
        } else {
            flushMarkdown()
        }

        return result.isEmpty ? [.markdown(text)] : result
    }
}

private enum MessagePart {
    case markdown(String)
    case code(language: String, code: String)
}

private struct CodeBlockView: View {
    let language: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language.isEmpty ? "Code" : language)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                } label: {
                    Label("Kopieren", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.10, blue: 0.14),
                        Color(red: 0.13, green: 0.16, blue: 0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
