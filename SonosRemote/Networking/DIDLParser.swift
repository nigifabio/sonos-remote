import Foundation

/// Parses a `ContentDirectory.Browse` result: a DIDL-Lite document containing
/// a flat list of `<item>` (playable) and `<container>` (drill-in/playlist)
/// elements. Expects `didl` already unescaped once (raw XML, not the
/// SOAP-escaped text still sitting inside a `<Result>` tag).
enum DIDLParser {
    static func parseItems(from didl: String, host: String) -> [BrowseItem] {
        let pattern = "<(item|container)\\b([^>]*)>([\\s\\S]*?)</\\1>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: didl, range: NSRange(didl.startIndex..., in: didl))

        return matches.compactMap { match -> BrowseItem? in
            guard let tagRange = Range(match.range(at: 1), in: didl),
                  let attrRange = Range(match.range(at: 2), in: didl),
                  let bodyRange = Range(match.range(at: 3), in: didl) else { return nil }

            let tagName = String(didl[tagRange])
            let attrs = XMLHelpers.allAttributes(in: String(didl[attrRange]))
            let body = String(didl[bodyRange])
            guard let id = attrs["id"] else { return nil }
            let parentID = attrs["parentID"] ?? ""

            let title = XMLHelpers.unescapeXML(XMLHelpers.value(ofTag: "dc:title", in: body) ?? "Unknown")
            let subtitle = XMLHelpers.unescapeXML(XMLHelpers.value(ofTag: "dc:creator", in: body) ?? "")
            let rawURI = XMLHelpers.value(ofTag: "res", in: body) ?? ""
            let uri = XMLHelpers.unescapeXML(rawURI)

            var albumArt: URL?
            if let rawArt = XMLHelpers.value(ofTag: "upnp:albumArtURI", in: body) {
                let art = XMLHelpers.unescapeXML(rawArt)
                albumArt = art.hasPrefix("http") ? URL(string: art) : URL(string: "http://\(host):1400\(art)")
            }

            // `body` is already "raw DIDL text" (single-escaped, e.g. "&amp;"
            // for a literal &) — exactly the form SOAPClient expects for a
            // metadata argument it will escape once more at send time.
            let metadata = """
            <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"><\(tagName) id="\(id)" parentID="\(parentID)" restricted="true">\(body)</\(tagName)></DIDL-Lite>
            """

            return BrowseItem(
                id: id, parentID: parentID, title: title, subtitle: subtitle,
                uri: uri, metadata: metadata, albumArtURL: albumArt,
                isContainer: tagName == "container"
            )
        }
    }
}
