import SwiftUI
import MarkdownUI
import core

// MARK: - Semantic Link Category
/// Categories for inline semantic annotation links in catalogue markdown.
/// URL format: `scheme://encoded_term` e.g. `landscape://the%20Alps`
enum SemanticLinkCategory: String, CaseIterable {
    case landscape
    case cuisine
    case dish
    case place
    
    /// Parse a URL into a semantic link category and decoded term.
    /// Returns nil for non-semantic URLs (e.g. regular http links).
    static func parse(_ url: URL) -> (category: SemanticLinkCategory, term: String)? {
        guard let scheme = url.scheme,
              let category = SemanticLinkCategory(rawValue: scheme) else {
            return nil
        }
        // Term is encoded as the host portion: scheme://encoded_term
        let term = url.host(percentEncoded: false) ?? ""
        return (category, term)
    }
}

// MARK: - Markdown Renderer
struct MarkdownRenderer: View {
    let markdown: String
    let config: JSONValue?
    
    @State private var tappedLink: (category: SemanticLinkCategory, term: String)?
    
    /// Preprocessed markdown with URL-encoded autolinks converted to proper markdown links
    private var processedMarkdown: String {
        preprocessSemanticAutolinks(markdown)
    }
    
    var body: some View {
        Markdown(processedMarkdown)
            .markdownTextStyle(\.text) {
                MarkdownUI.FontFamily(.custom(FontFamily.sansRegular))
                MarkdownUI.FontSize(TypographyScale.article0.baseSize)
                MarkdownUI.ForegroundColor(Color.textSecondary)
            }
            .markdownTextStyle(\.strong) {
                MarkdownUI.FontWeight(.semibold)
                MarkdownUI.ForegroundColor(Color.textPrimary)
            }
            .markdownTextStyle(\.link) {
                MarkdownUI.ForegroundColor(Color("AccentColor"))
                MarkdownUI.FontWeight(.medium)
                MarkdownUI.UnderlineStyle(.init(pattern: .dot, color: Color("AccentColor").opacity(0.5)))
            }
            .markdownBlockStyle(\.paragraph) { configuration in
                configuration.label
                    .padding(.horizontal, Spacing.current.textSideMargin)
            }
            .markdownBlockStyle(\.heading2) { configuration in
                configuration.label
                    .markdownTextStyle {
                        MarkdownUI.FontFamily(.custom(FontFamily.sansExtraLight))
                        MarkdownUI.FontSize(TypographyScale.article3.baseSize)
                        MarkdownUI.ForegroundColor(Color.textPrimary)
                    }
                    .padding(.top, Spacing.current.spaceXs)
                    .padding(.horizontal, Spacing.current.textSideMargin)
            }
            .markdownBlockStyle(\.heading3) { configuration in
                configuration.label
                    .markdownTextStyle {
                        MarkdownUI.FontWeight(.bold)
                        MarkdownUI.FontSize(TypographyScale.article1.baseSize)
                        MarkdownUI.ForegroundColor(Color.textPrimary)
                    }
                    .padding(.horizontal, Spacing.current.textSideMargin)
            }
            .markdownBlockStyle(\.blockquote) { configuration in
                configuration.label
                    .markdownTextStyle {
                        MarkdownUI.FontFamily(.custom(FontFamily.sansRegular))
                        MarkdownUI.FontSize(TypographyScale.article0.baseSize)
                        MarkdownUI.ForegroundColor(Color.textPrimary)
                    }
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color("AccentColor"))
                            .frame(width: 4)
                    }
                    .padding(.horizontal, Spacing.current.spaceM)
                    .padding(.bottom, Spacing.current.spaceS)

            }
            .markdownBlockStyle(\.table) { configuration in
                configuration.label
                    .markdownTableBorderStyle(.init(color: .clear))
                    .markdownMargin(top: 16, bottom: 16)
            }
            .environment(\.openURL, OpenURLAction { url in
                if let parsed = SemanticLinkCategory.parse(url) {
                    tappedLink = parsed
                    return .handled
                }
                return .systemAction
            })
    }
}

// MARK: - Semantic Autolink Preprocessing
/// Preprocesses markdown to fix semantic link display issues:
/// 1. Converts bare semantic URLs to properly formatted markdown links
/// 2. Decodes URL-encoded text in existing link text
///
/// Example transformations:
/// - `landscape://the%20Alps` → `[the Alps](landscape://the%20Alps)`
/// - `[Dom%20Luís](place://Dom%20Luís)` → `[Dom Luís](place://Dom%20Luís)`
/// - `place://Avenida%20da%20Boavista` → `[Avenida da Boavista](place://Avenida%20da%20Boavista)`
private func preprocessSemanticAutolinks(_ markdown: String) -> String {
    var result = markdown
    
    // Step 1: Decode URL-encoded text in existing markdown links with semantic schemes
    // Pattern: [encoded%20text](scheme://url)
    let linkPattern = #"\[([^\]]+)\]\((landscape|cuisine|dish|place)://[^\)]+\)"#
    if let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: []) {
        let nsString = result as NSString
        let matches = linkRegex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
        
        // Process in reverse to preserve indices
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }
            
            let fullMatch = nsString.substring(with: match.range)
            let linkTextRange = match.range(at: 1)
            let linkText = nsString.substring(with: linkTextRange)
            
            // Decode the link text
            if let decodedText = linkText.removingPercentEncoding, decodedText != linkText {
                // Only replace if decoding actually changed something
                let updatedLink = fullMatch.replacingOccurrences(of: "[\(linkText)]", with: "[\(decodedText)]")
                result = (result as NSString).replacingCharacters(in: match.range, with: updatedLink) as String
            }
        }
    }
    
    // Step 2: Convert bare semantic URLs to properly formatted markdown links
    // Pattern matches semantic scheme autolinks not already in markdown link syntax
    let autolinkPattern = #"(?<!\]\()(?<!\[.*\]\()(landscape|cuisine|dish|place)://([^\s\)]+)"#
    if let autolinkRegex = try? NSRegularExpression(pattern: autolinkPattern, options: []) {
        let nsString = result as NSString
        let matches = autolinkRegex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
        
        // Process matches in reverse order to preserve string indices
        for match in matches.reversed() {
            let currentNSString = result as NSString
            let fullMatch = currentNSString.substring(with: match.range)
            
            // Extract scheme and encoded term
            guard let url = URL(string: fullMatch),
                  url.scheme != nil,
                  let encodedTerm = url.host(percentEncoded: true) else {
                continue
            }
            
            // Decode the term for display
            let decodedTerm = encodedTerm.removingPercentEncoding ?? encodedTerm

            // If the URL is already inside markdown link destination "(...)", skip it.
            if match.range.location > 0 {
                let previousChar = currentNSString.substring(with: NSRange(location: match.range.location - 1, length: 1))
                if previousChar == "(" {
                    continue
                }
            }

            let textBeforeURL = currentNSString.substring(to: match.range.location)
            let normalizedDecodedTerm = decodedTerm
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

            // Collapse malformed "term + semantic_url" into one linked term.
            // Handles plain and emphasized forms such as:
            // - "Lisbon place://Lisbon"
            // - "**Afonso I**place://Afonso%20I"
            // - "*Francesinha*  dish://Francesinha"
            let duplicatePattern = #"(?s)(\*\*([^\*]+)\*\*|\*([^\*]+)\*|_([^_]+)_|([^\s\[\]\(\)\*_:][^\[\]\(\)]*?))\s*$"#
            if let duplicateRegex = try? NSRegularExpression(pattern: duplicatePattern, options: []) {
                let beforeRange = NSRange(location: 0, length: (textBeforeURL as NSString).length)
                if let duplicateMatch = duplicateRegex.firstMatch(in: textBeforeURL, options: [], range: beforeRange) {
                    let matchedPrefix = (textBeforeURL as NSString).substring(with: duplicateMatch.range(at: 1))
                    let extractedDisplayTerm: String
                    let emphasisMarker: String

                    if duplicateMatch.range(at: 2).location != NSNotFound {
                        extractedDisplayTerm = (textBeforeURL as NSString).substring(with: duplicateMatch.range(at: 2))
                        emphasisMarker = "**"
                    } else if duplicateMatch.range(at: 3).location != NSNotFound {
                        extractedDisplayTerm = (textBeforeURL as NSString).substring(with: duplicateMatch.range(at: 3))
                        emphasisMarker = "*"
                    } else if duplicateMatch.range(at: 4).location != NSNotFound {
                        extractedDisplayTerm = (textBeforeURL as NSString).substring(with: duplicateMatch.range(at: 4))
                        emphasisMarker = "_"
                    } else if duplicateMatch.range(at: 5).location != NSNotFound {
                        extractedDisplayTerm = (textBeforeURL as NSString).substring(with: duplicateMatch.range(at: 5))
                        emphasisMarker = ""
                    } else {
                        extractedDisplayTerm = matchedPrefix
                        emphasisMarker = ""
                    }

                    let normalizedExtractedTerm = extractedDisplayTerm
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

                    if normalizedExtractedTerm == normalizedDecodedTerm {
                        let replacementRange = NSRange(
                            location: duplicateMatch.range(at: 1).location,
                            length: match.range.location + match.range.length - duplicateMatch.range(at: 1).location
                        )
                        let linkedTerm = "[\(decodedTerm)](\(fullMatch))"
                        let replacement = emphasisMarker.isEmpty
                            ? linkedTerm
                            : "\(emphasisMarker)\(linkedTerm)\(emphasisMarker)"

                        result = (result as NSString).replacingCharacters(in: replacementRange, with: replacement) as String
                        continue
                    }
                }
            }

            // Check surrounding characters to determine if we need to add spaces
            let needsLeadingSpace = match.range.location > 0 &&
                !currentNSString.substring(with: NSRange(location: match.range.location - 1, length: 1)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let trailingCharacterLocation = match.range.location + match.range.length
            let needsTrailingSpace = trailingCharacterLocation < currentNSString.length &&
                !currentNSString.substring(with: NSRange(location: trailingCharacterLocation, length: 1)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            // Create proper markdown link with appropriate spacing
            let leadingSpace = needsLeadingSpace ? " " : ""
            let trailingSpace = needsTrailingSpace ? " " : ""
            let replacement = "\(leadingSpace)[\(decodedTerm)](\(fullMatch))\(trailingSpace)"

            result = (result as NSString).replacingCharacters(in: match.range, with: replacement) as String
        }
    }
    
    return result
}
