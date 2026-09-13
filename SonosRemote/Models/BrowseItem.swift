import Foundation

/// One entry from a Sonos `ContentDirectory` Browse call — a Favorite, a
/// Playlist, a local-library artist/album/track, or a queue entry. They're
/// all the same DIDL-Lite shape, just under different root ObjectIDs.
struct BrowseItem: Identifiable, Hashable {
    let id: String            // ObjectID, e.g. "FV:2/1", "SQ:3", "Q:0/5"
    let parentID: String
    let title: String
    let subtitle: String      // artist/creator when present, else empty
    let uri: String           // res — pass straight to CurrentURI
    let metadata: String      // raw DIDL-Lite <item>/<container> fragment — pass straight to CurrentURIMetaData
    let albumArtURL: URL?
    let isContainer: Bool     // true = playlist/album/folder (drill in or "play all"); false = directly playable
}

/// Well-known Sonos ContentDirectory root ObjectIDs.
enum BrowseRoot {
    static let favorites = "FV:2"
    static let playlists = "SQ:"
    static let queue = "Q:0"
    static let musicLibraryRoot = "A:"
    static let artists = "A:ARTIST"
    static let albums = "A:ALBUM"
    static let genres = "A:GENRE"
    static let tracks = "A:TRACKS"
}
