import Foundation

enum XMLHelpers {
    /// Extracts the text content of the first `<tag>...</tag>` occurrence.
    /// Sonos SOAP responses are flat enough that a targeted regex is reliable
    /// and far simpler than a full XMLParser delegate for these fields.
    static func value(ofTag tag: String, in xml: String) -> String? {
        // \b anchors the tag name boundary so e.g. "upnp:album" doesn't also
        // match inside "upnp:albumArtURI".
        let escaped = NSRegularExpression.escapedPattern(for: tag)
        let pattern = "<\(escaped)\\b[^>]*>([\\s\\S]*?)</\(escaped)>"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[range])
    }

    /// Extracts all attribute values for a given self-closed/opening tag and attribute name.
    static func attributeValues(tag: String, attribute: String, in xml: String) -> [[String: String]] {
        let tagPattern = "<\(NSRegularExpression.escapedPattern(for: tag))\\b([^>]*)/?>"
        guard let regex = try? NSRegularExpression(pattern: tagPattern) else { return [] }
        let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
        return matches.compactMap { match -> [String: String]? in
            guard let attrRange = Range(match.range(at: 1), in: xml) else { return nil }
            return allAttributes(in: String(xml[attrRange]))
        }
    }

    static func allAttributes(in attrString: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = "(\\w+)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let matches = regex.matches(in: attrString, range: NSRange(attrString.startIndex..., in: attrString))
        for match in matches {
            guard let keyRange = Range(match.range(at: 1), in: attrString),
                  let valRange = Range(match.range(at: 2), in: attrString) else { continue }
            result[String(attrString[keyRange])] = unescapeXML(String(attrString[valRange]))
        }
        return result
    }

    static func unescapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Sonos encodes track duration/position as "H:MM:SS".
    static func seconds(fromSonosTime time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return 0 }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }
}
