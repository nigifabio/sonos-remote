import Foundation

/// Scans a folder on this Mac for playable audio files and turns them into
/// `BrowseItem`s pointing at `LocalHTTPServer`-served URLs, so `LibraryView`
/// can browse and play personal music that was never indexed as a Sonos
/// -attached NAS share (that's what "Local Library"/`A:` already covers).
enum LocalLibraryService {
    static let defaultsKey = "localLibraryPath"
    static let port: UInt16 = 57123
    static let pathPrefix = "/library/"

    static let supportedExtensions: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "aiff", "alac"]

    private static let contentTypes: [String: String] = [
        "mp3": "audio/mpeg", "m4a": "audio/mp4", "aac": "audio/aac",
        "flac": "audio/flac", "wav": "audio/wav", "aiff": "audio/aiff", "alac": "audio/mp4"
    ]

    static func contentType(forExtension ext: String) -> String {
        contentTypes[ext.lowercased()] ?? "application/octet-stream"
    }

    /// Immediate children of `relativePath` (empty = the library root) under
    /// `root` — subfolders first, then playable audio files, both
    /// alphabetical. Unsupported file types are silently skipped.
    static func list(root: URL, relativePath: String) -> [BrowseItem] {
        let dirURL = relativePath.isEmpty ? root : root.appendingPathComponent(relativePath)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dirURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        let items: [BrowseItem] = entries.compactMap { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let childRelative = relativePath.isEmpty ? url.lastPathComponent : "\(relativePath)/\(url.lastPathComponent)"
            if isDir {
                return BrowseItem(id: childRelative, parentID: relativePath, title: url.lastPathComponent,
                                   subtitle: "", uri: "", metadata: "", albumArtURL: nil, isContainer: true)
            }
            guard supportedExtensions.contains(url.pathExtension.lowercased()),
                  let ip = LocalHTTPServer.primaryLANAddress(),
                  let uri = trackURL(ip: ip, relativePath: childRelative) else { return nil }
            let title = url.deletingPathExtension().lastPathComponent
            return BrowseItem(id: childRelative, parentID: relativePath, title: title, subtitle: "",
                               uri: uri.absoluteString, metadata: didlMetadata(title: title),
                               albumArtURL: nil, isContainer: false)
        }
        return items.sorted {
            if $0.isContainer != $1.isContainer { return $0.isContainer }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    /// Every playable file directly inside `relativePath` (non-recursive) —
    /// backs "play all" on a folder row.
    static func files(root: URL, relativePath: String) -> [BrowseItem] {
        list(root: root, relativePath: relativePath).filter { !$0.isContainer }
    }

    static func trackURL(ip: String, relativePath: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = ip
        components.port = Int(port)
        components.path = pathPrefix + relativePath
        return components.url
    }

    /// Raw (unescaped) DIDL-Lite metadata — `SOAPClient.call` escapes
    /// argument values exactly once when it builds the envelope, so this
    /// must always be passed through unescaped.
    private static func didlMetadata(title: String) -> String {
        """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:dc="http://purl.org/dc/elements/1.1/"><item id="local" parentID="-1" restricted="1"><dc:title>\(title)</dc:title><upnp:class>object.item.audioItem.musicTrack</upnp:class></item></DIDL-Lite>
        """
    }
}
