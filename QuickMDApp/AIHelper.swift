#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(macOS 26.0, *)
enum AIHelper {

    static var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available:
            return true
        default:
            return false
        }
    }

    // MARK: - Text Transformations

    enum Action: String, CaseIterable {
        case improveWriting = "Improve Writing"
        case fixGrammar = "Fix Grammar & Spelling"
        case makeConcise = "Make Concise"
        case makeLonger = "Expand & Elaborate"
        case simplify = "Simplify Language"
        case professional = "Professional Tone"
        case casual = "Casual Tone"
        case summarize = "Summarize"
        case bulletPoints = "Convert to Bullet Points"
        case fixMarkdown = "Fix Markdown"

        var systemPrompt: String {
            switch self {
            case .fixMarkdown:
                return """
                    You are a Markdown syntax fixer. You receive the user's EXACT document and return it with ONLY formatting fixes applied. \
                    CRITICAL: You MUST preserve the user's original text, words, and meaning exactly. Do NOT generate new content, \
                    examples, tutorials, or placeholder text. Do NOT replace the user's content with something else. \
                    Only fix Markdown syntax issues: mismatched bold/italic markers, unpaired links/brackets, \
                    unclosed code fences, broken table formatting, inconsistent list markers. \
                    Use - for unordered lists. Remove empty lines between consecutive list items to make lists compact. \
                    Add blank lines between sections if missing. Remove trailing spaces. \
                    If frontmatter exists, ensure it is properly delimited with ---. \
                    Output ONLY the user's document with fixes applied. No explanations, no code fences wrapping the output. \
                    If the input is already correct, output it unchanged.
                    """
            case .improveWriting:
                return "You are a writing assistant. Improve the clarity, flow, and quality of the given markdown text. Keep the same meaning and markdown formatting. Return ONLY the improved text, no explanations."
            case .fixGrammar:
                return "You are a proofreader. Fix all grammar, spelling, and punctuation errors in the given markdown text. Keep the same meaning and markdown formatting. Return ONLY the corrected text, no explanations."
            case .makeConcise:
                return "You are an editor. Make the given markdown text more concise while preserving key information and markdown formatting. Return ONLY the shortened text, no explanations."
            case .makeLonger:
                return "You are a writing assistant. Expand the given markdown text with more detail, examples, or elaboration while maintaining markdown formatting. Return ONLY the expanded text, no explanations."
            case .simplify:
                return "You are a writing assistant. Rewrite the given markdown text using simpler words and shorter sentences. Keep markdown formatting. Return ONLY the simplified text, no explanations."
            case .professional:
                return "You are a writing assistant. Rewrite the given markdown text in a professional, formal tone. Keep markdown formatting. Return ONLY the rewritten text, no explanations."
            case .casual:
                return "You are a writing assistant. Rewrite the given markdown text in a casual, friendly tone. Keep markdown formatting. Return ONLY the rewritten text, no explanations."
            case .summarize:
                return "You are a writing assistant. Summarize the given markdown text into a brief overview. Use markdown formatting. Return ONLY the summary, no explanations."
            case .bulletPoints:
                return "You are a writing assistant. Convert the given text into a well-organized markdown bullet point list. Return ONLY the bullet points, no explanations."
            }
        }
    }

    /// Strip wrapping ```markdown fences that the model sometimes adds.
    private static func stripCodeFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = result.range(of: #"^```\w*\n"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        if let range = result.range(of: #"\n```\s*$"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result
    }

    /// Process a single AI call, returning original on failure or if the result is too different.
    private static func processOnce(_ text: String, instructions: String) async -> String {
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: text)
            let result = stripCodeFences(response.content)
            // Reject hallucinated output: if the result shares too few words with the original, discard it
            if isTooDistant(original: text, result: result) {
                return text
            }
            return result
        } catch {
            return text
        }
    }

    /// Check if the AI output is too different from the original (likely hallucinated).
    private static func isTooDistant(original: String, result: String) -> Bool {
        let originalWords = Set(original.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init))
        let resultWords = Set(result.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init))
        guard !originalWords.isEmpty else { return false }
        let overlap = originalWords.intersection(resultWords).count
        let ratio = Double(overlap) / Double(originalWords.count)
        // If less than 50% of original words appear in the result, it's likely hallucinated
        return ratio < 0.5
    }

    /// True if a chunk should skip AI (code blocks, tables, frontmatter, link-heavy).
    private static func shouldSkip(_ text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 2 else { return false }
        var skipLines = 0
        var inFence = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inFence.toggle(); skipLines += 1; continue }
            if inFence { skipLines += 1; continue }
            // Indented code
            if line.hasPrefix("    ") || line.hasPrefix("\t") { skipLines += 1; continue }
            // Table rows
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") { skipLines += 1; continue }
            // Frontmatter delimiter
            if trimmed == "---" { skipLines += 1; continue }
            // Lines that are just links/images
            if trimmed.hasPrefix("![") || trimmed.hasPrefix("[") && trimmed.contains("](") { skipLines += 1; continue }
            // Blank lines
            if trimmed.isEmpty { skipLines += 1 }
        }
        return skipLines > lines.count * 2 / 3
    }

    /// Extract only the prose portions of markdown, keeping structure markers for context.
    /// Returns (proseText, fullLines, proseLineIndices) so we can splice results back.
    private static func extractProse(_ text: String) -> (prose: String, allLines: [String], proseRanges: [(start: Int, end: Int)]) {
        let lines = text.components(separatedBy: "\n")
        var ranges: [(start: Int, end: Int)] = []
        var inFence = false
        var inFrontmatter = false
        var rangeStart: Int? = nil

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Track fenced code blocks
            if trimmed.hasPrefix("```") { inFence.toggle() }
            // Track frontmatter
            if i == 0 && trimmed == "---" { inFrontmatter = true }
            else if inFrontmatter && trimmed == "---" { inFrontmatter = false; continue }

            let isSkip = inFence || inFrontmatter
                || (line.hasPrefix("    ") || line.hasPrefix("\t"))  // indented code
                || (trimmed.hasPrefix("|") && trimmed.hasSuffix("|"))  // tables
                || trimmed.isEmpty

            if isSkip {
                if let start = rangeStart {
                    ranges.append((start, i - 1))
                    rangeStart = nil
                }
            } else {
                if rangeStart == nil { rangeStart = i }
            }
        }
        if let start = rangeStart { ranges.append((start, lines.count - 1)) }

        let proseLines = ranges.flatMap { lines[$0.start...$0.end] }
        return (proseLines.joined(separator: "\n"), lines, ranges)
    }

    /// Transform text using Apple Intelligence.
    /// Extracts prose only, sends one AI call, splices result back in.
    static func transform(_ text: String, action: Action) async -> String {
        // Small text with no skippable content — single call
        if text.count <= 8000 && !shouldSkip(text) {
            return await processOnce(text, instructions: action.systemPrompt)
        }

        // Extract just the prose, skip code/tables/frontmatter
        let (prose, allLines, ranges) = extractProse(text)
        if prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text // nothing to transform
        }

        // Process prose in a single call if small enough, otherwise minimal chunks
        let transformedProse: String
        if prose.count <= 8000 {
            transformedProse = await processOnce(prose, instructions: action.systemPrompt)
        } else {
            // Split prose into ~4000 char chunks (fewer, bigger calls)
            let proseChunks = splitProse(prose, maxChars: 7000)
            var results: [String] = []
            for chunk in proseChunks {
                results.append(await processOnce(chunk, instructions: action.systemPrompt))
            }
            transformedProse = results.joined(separator: "\n")
        }

        // Splice transformed prose back into original structure
        let transformedLines = transformedProse.components(separatedBy: "\n")
        var result = allLines
        var transformedIdx = 0
        for range in ranges {
            let originalCount = range.end - range.start + 1
            let available = min(originalCount, transformedLines.count - transformedIdx)
            guard available > 0 else { break }
            for j in 0..<available {
                result[range.start + j] = transformedLines[transformedIdx + j]
            }
            // If AI returned fewer lines, blank out the rest
            for j in available..<originalCount {
                result[range.start + j] = ""
            }
            transformedIdx += available
        }
        // If AI returned extra lines, append them
        if transformedIdx < transformedLines.count {
            result.append(contentsOf: transformedLines[transformedIdx...])
        }

        return result.joined(separator: "\n")
    }

    /// Split prose text into chunks at paragraph boundaries.
    private static func splitProse(_ text: String, maxChars: Int) -> [String] {
        let paragraphs = text.components(separatedBy: "\n\n")
        var chunks: [String] = []
        var current = ""
        for para in paragraphs {
            if current.count + para.count + 2 > maxChars && !current.isEmpty {
                chunks.append(current)
                current = para
            } else {
                current += (current.isEmpty ? "" : "\n\n") + para
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    // MARK: - URL Import Cleanup

    static func cleanupImportedMarkdown(_ markdown: String) async -> String {
        let instructions = """
            You are a markdown cleanup assistant. You receive raw markdown that was converted from a web page. \
            Clean it up: remove navigation artifacts, fix formatting issues, ensure proper heading hierarchy, \
            remove duplicate content, and make it well-structured. Keep all meaningful content. \
            Return ONLY the cleaned markdown text directly. Do NOT wrap it in code fences. No explanations.
            """
        // For cleanup, send prose only — same strategy
        let (prose, _, _) = extractProse(markdown)
        if prose.isEmpty { return markdown }
        if prose.count <= 8000 {
            return await processOnce(markdown.count <= 8000 ? markdown : prose, instructions: instructions)
        }
        let chunks = splitProse(prose, maxChars: 7000)
        var results: [String] = []
        for chunk in chunks {
            results.append(await processOnce(chunk, instructions: instructions))
        }
        return results.joined(separator: "\n\n")
    }

    // MARK: - Smart Features

    static func generateFrontmatter(for markdown: String) async throws -> String {
        let session = LanguageModelSession(instructions: """
            You are a metadata assistant. Given a markdown document, generate YAML frontmatter with: \
            title, description (1-2 sentences), and tags (3-5 relevant tags). \
            Return ONLY the frontmatter block starting with --- and ending with ---, no other text. \
            Do NOT wrap it in code fences.
            """)
        let response = try await session.respond(to: String(markdown.prefix(3000)))
        return stripCodeFences(response.content)
    }
}
#endif
