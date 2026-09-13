import Foundation

/// One entry in the locally-tracked "recently played" log. Sonos doesn't
/// expose play history over UPnP, so this app builds its own by watching
/// for track changes (from GENA events / polling) and by recording what it
/// itself just told a room to play (e.g. from the Library browser, where we
/// know the exact Favorite/Playlist name — something we can't recover from
/// track metadata alone once something else is already playing it).
struct PlaybackHistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let groupName: String
    let title: String
    let artist: String
    let album: String
    let service: MusicService
    /// The Favorite/Playlist name, when this play was initiated from this
    /// app's Library browser and we therefore know it exactly. Nil when the
    /// entry was only observed as a track change from an unknown source
    /// (the official Sonos app, a physical remote, Spotify Connect, etc).
    let sourceLabel: String?

    init(groupName: String, title: String, artist: String, album: String, service: MusicService, sourceLabel: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.groupName = groupName
        self.title = title
        self.artist = artist
        self.album = album
        self.service = service
        self.sourceLabel = sourceLabel
    }
}
