import Foundation
import WidgetKit

@MainActor
final class SonosViewModel: ObservableObject {
    @Published var groups: [SonosGroup] = []
    @Published var deviceVolumes: [String: Int] = [:]     // device UUID -> volume
    @Published var groupVolumes: [String: Int] = [:]      // group ID -> volume
    @Published var deviceMutes: [String: Bool] = [:]       // device UUID -> muted
    @Published var deviceGenerations: [String: SonosSystemGeneration] = [:] // device UUID -> S1/S2/unknown
    @Published var groupMutes: [String: Bool] = [:]        // group ID -> muted
    @Published var nowPlaying: [String: TrackInfo] = [:]  // group ID -> track
    @Published var transportStates: [String: TransportState] = [:]
    @Published var isDiscovering = false
    @Published var isBusyGrouping = false
    @Published var errorMessage: String?
    @Published var selectedGroupID: String?
    @Published private(set) var playbackHistory: [PlaybackHistoryEntry] = []

    #if os(macOS)
    let intercom = IntercomService()
    #endif

    private var pollTask: Task<Void, Never>?
    private var lastLoggedTrack: [String: TrackInfo] = [:] // group ID -> last track we recorded to history
    private let defaults: UserDefaults
    private static let historyDefaultsKey = "playbackHistory"
    private static let historyLimit = 50

    /// `defaults` is injectable so tests can use an isolated `UserDefaults`
    /// suite instead of `.standard` — sharing `.standard` across test cases
    /// caused real flakiness under parallel test execution.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        playbackHistory = Self.loadHistory(from: defaults)
    }

    /// Most recently played track across every room, newest first.
    var lastPlayed: PlaybackHistoryEntry? { playbackHistory.first }

    /// Most recent Spotify play where we know the specific Favorite/Playlist
    /// name (i.e. it was started from this app's Library browser — Sonos
    /// doesn't expose "what playlist is this track from" for anything
    /// started elsewhere, like the official app or Spotify Connect).
    var lastSpotifyPlaylist: PlaybackHistoryEntry? {
        playbackHistory.first { $0.service == .spotify && $0.sourceLabel != nil }
    }

    /// Falls back to the most recent Spotify *track* (playlist name unknown)
    /// when we've never played a Spotify Favorite/Playlist from this app.
    var lastSpotifyTrack: PlaybackHistoryEntry? {
        playbackHistory.first { $0.service == .spotify }
    }

    private static func loadHistory(from defaults: UserDefaults) -> [PlaybackHistoryEntry] {
        guard let data = defaults.data(forKey: historyDefaultsKey),
              let entries = try? JSONDecoder().decode([PlaybackHistoryEntry].self, from: data) else { return [] }
        return entries
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(playbackHistory) else { return }
        defaults.set(data, forKey: Self.historyDefaultsKey)
    }

    /// Records a history entry if the group's track actually changed since
    /// the last one we logged (avoids re-logging the same song every poll).
    func recordHistoryIfChanged(group: SonosGroup, track: TrackInfo) {
        guard !track.title.isEmpty else { return }
        if let last = lastLoggedTrack[group.id], last.title == track.title, last.artist == track.artist { return }
        lastLoggedTrack[group.id] = track
        let entry = PlaybackHistoryEntry(
            groupName: group.name, title: track.title, artist: track.artist,
            album: track.album, service: track.service
        )
        playbackHistory.insert(entry, at: 0)
        if playbackHistory.count > Self.historyLimit {
            playbackHistory.removeLast(playbackHistory.count - Self.historyLimit)
        }
        saveHistory()
    }

    /// Plays a Favorite/Playlist/Library item from `LibraryView` and records
    /// it to history with its exact name — the one case where we actually
    /// know the playlist, since we're the one who just told Sonos to play it.
    func playLibraryItem(_ item: BrowseItem, in group: SonosGroup) {
        guard let device = group.coordinator else { return }
        Task {
            try? await SonosController.play(item, on: device)
            let service = MusicService.detect(from: item.uri)
            let entry = PlaybackHistoryEntry(
                groupName: group.name, title: item.title, artist: item.subtitle,
                album: "", service: service, sourceLabel: item.title
            )
            lastLoggedTrack[group.id] = TrackInfo(title: item.title, artist: item.subtitle)
            playbackHistory.insert(entry, at: 0)
            if playbackHistory.count > Self.historyLimit {
                playbackHistory.removeLast(playbackHistory.count - Self.historyLimit)
            }
            saveHistory()
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refreshNowPlaying(for: group)
        }
    }

    var allDevices: [SonosDevice] { groups.flatMap(\.members) }
    var allDevicesSorted: [SonosDevice] { allDevices.sorted { $0.name < $1.name } }
    var isPartyMode: Bool { groups.count == 1 && (groups.first?.members.count ?? 0) > 1 }

    var selectedGroup: SonosGroup? {
        groups.first { $0.id == selectedGroupID } ?? groups.first
    }

    func group(containing device: SonosDevice) -> SonosGroup? {
        groups.first { $0.members.contains(device) }
    }

    func generation(for device: SonosDevice) -> SonosSystemGeneration {
        deviceGenerations[device.uuid] ?? .unknown
    }

    /// A group's generation, taken from its coordinator — S1 and S2 devices
    /// can never share a household, so every member of a real group is
    /// necessarily the same generation.
    func generation(for group: SonosGroup) -> SonosSystemGeneration {
        group.coordinator.map { generation(for: $0) } ?? .unknown
    }

    /// The song playing in `device`'s room (shared across the whole group it's in, if any).
    func trackInfo(for device: SonosDevice) -> TrackInfo? {
        group(containing: device).flatMap { nowPlaying[$0.id] }
    }

    func start() {
        setUpLiveEvents()
        Task { await refreshTopology() }
        // GENA push events (see setUpLiveEvents) handle near-instant updates;
        // this poll is just the safety net for anything a dropped/missed
        // event notification would otherwise leave stale.
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await self?.refreshNowPlayingAndVolumes()
            }
        }
    }

    /// Wires GENA (UPnP eventing) push notifications straight into our
    /// published state, so play/pause/volume changes — including ones made
    /// from the official Sonos app or a physical remote — appear immediately
    /// instead of waiting for the next poll.
    private func setUpLiveEvents() {
        let manager = GENASubscriptionManager.shared
        manager.onTransportChange = { [weak self] host, state in
            guard let self, let group = self.groups.first(where: { $0.coordinator?.host == host }) else { return }
            self.transportStates[group.id] = state
            Task { await self.refreshNowPlaying(for: group) }
        }
        manager.onVolumeChange = { [weak self] host, volume in
            guard let self, let device = self.allDevices.first(where: { $0.host == host }) else { return }
            self.deviceVolumes[device.uuid] = volume
            if let group = self.group(containing: device), group.coordinatorUUID == device.uuid {
                self.groupVolumes[group.id] = volume
            }
            self.publishWidgetSnapshot()
        }
        manager.start()
    }

    func refreshTopology() async {
        isDiscovering = true
        let discovered = await SonosController.discoverGroups()
        isDiscovering = false
        await applyDiscoveredTopology(discovered)
    }

    /// Re-fetches topology from a device we already know about instead of
    /// re-running full SSDP discovery (which always takes ~3-4s even when
    /// every device is already known). Used right after a grouping action
    /// (Party Mode, pair/unpair), where the IPs haven't changed — only the
    /// grouping has — so this turns a multi-second silent wait into a
    /// sub-second one. Falls back to full discovery if the known host is
    /// unreachable (e.g. it just got unplugged).
    private func refreshTopologyFast() async {
        guard let knownHost = groups.first?.coordinator?.host ?? allDevices.first?.host else {
            await refreshTopology()
            return
        }
        if let discovered = try? await SonosController.fetchTopology(bootstrapHost: knownHost), !discovered.isEmpty {
            await applyDiscoveredTopology(discovered)
        } else {
            await refreshTopology()
        }
    }

    private func applyDiscoveredTopology(_ discovered: [SonosGroup]) async {
        if discovered.isEmpty {
            errorMessage = "No Sonos speakers found on this network."
            return
        }
        errorMessage = nil
        groups = discovered
        if selectedGroupID == nil || !discovered.contains(where: { $0.id == selectedGroupID }) {
            selectedGroupID = discovered.first?.id
        }
        await GENASubscriptionManager.shared.updateSubscriptions(coordinatorHosts: discovered.compactMap { $0.coordinator?.host })
        async let generations = SonosController.detectGenerations(for: discovered.flatMap(\.members))
        await refreshNowPlayingAndVolumes()
        deviceGenerations = await generations
    }

    /// True the moment a second Sonos household — running the *other*
    /// generation — is detected on the network (Sonos explicitly supports
    /// running S1 and S2 households side by side during a phased upgrade).
    var hasMixedGenerations: Bool {
        let generations = Set(allDevices.compactMap { deviceGenerations[$0.uuid] }.filter { $0 != .unknown })
        return generations.count > 1
    }

    /// Refreshes just one group's now-playing/transport/volume — used after a
    /// GENA transport-change event so we don't wait for the full poll cycle
    /// just to pick up the new track's title/artist/art.
    private func refreshNowPlaying(for group: SonosGroup) async {
        guard let coordinator = group.coordinator else { return }
        if let track = try? await SonosController.trackInfo(coordinator) {
            nowPlaying[group.id] = track
            recordHistoryIfChanged(group: group, track: track)
        }
        if let state = try? await SonosController.transportState(coordinator) { transportStates[group.id] = state }
        publishWidgetSnapshot()
    }

    func refreshNowPlayingAndVolumes() async {
        for group in groups {
            guard let coordinator = group.coordinator else { continue }
            async let track = try? SonosController.trackInfo(coordinator)
            async let state = try? SonosController.transportState(coordinator)
            async let gVolume = try? SonosController.groupVolume(group)
            async let gMute = try? SonosController.isGroupMuted(group)
            if let track = await track {
                nowPlaying[group.id] = track
                recordHistoryIfChanged(group: group, track: track)
            }
            if let state = await state { transportStates[group.id] = state }
            if let gVolume = await gVolume { groupVolumes[group.id] = gVolume }
            if let gMute = await gMute { groupMutes[group.id] = gMute }

            for member in group.members {
                if let vol = try? await SonosController.volume(member) {
                    deviceVolumes[member.uuid] = vol
                }
                if let muted = try? await SonosController.isMuted(member) {
                    deviceMutes[member.uuid] = muted
                }
            }
        }
        publishWidgetSnapshot()
    }

    /// Writes the current state to the App Group container so the widget
    /// extension (which can't reach the LAN for discovery itself) can render
    /// live data, then asks WidgetKit to redraw any placed widgets.
    private func publishWidgetSnapshot() {
        let rooms = groups.flatMap { group in
            group.members.map { device in
                WidgetRoomSnapshot(
                    id: device.uuid, name: device.name, host: device.host,
                    volume: deviceVolumes[device.uuid] ?? 0,
                    groupID: group.id, groupCoordinatorUUID: group.coordinatorUUID
                )
            }
        }
        let nowPlayingByGroup = nowPlaying.reduce(into: [String: WidgetNowPlaying]()) { dict, entry in
            let (groupID, track) = entry
            dict[groupID] = WidgetNowPlaying(
                title: track.title, artist: track.artist,
                isPlaying: transportStates[groupID] == .playing
            )
        }
        let snapshot = WidgetSnapshot(
            rooms: rooms, nowPlayingByGroup: nowPlayingByGroup,
            isPartyMode: isPartyMode, updatedAt: Date()
        )
        WidgetSharedStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Transport controls

    func togglePlayPause(_ group: SonosGroup) {
        guard let coordinator = group.coordinator else { return }
        let isPlaying = transportStates[group.id] == .playing
        Task {
            if isPlaying {
                try? await SonosController.pause(coordinator)
            } else {
                try? await SonosController.play(coordinator)
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            if let state = try? await SonosController.transportState(coordinator) {
                transportStates[group.id] = state
            }
        }
    }

    func next(_ group: SonosGroup) {
        guard let coordinator = group.coordinator else { return }
        Task { try? await SonosController.next(coordinator) }
    }

    func previous(_ group: SonosGroup) {
        guard let coordinator = group.coordinator else { return }
        Task { try? await SonosController.previous(coordinator) }
    }

    // MARK: - Volume

    func setGroupVolume(_ group: SonosGroup, to value: Int) {
        groupVolumes[group.id] = value
        Task { try? await SonosController.setGroupVolume(group, to: value) }
    }

    func setDeviceVolume(_ device: SonosDevice, to value: Int) {
        deviceVolumes[device.uuid] = value
        Task { try? await SonosController.setVolume(device, to: value) }
    }

    func toggleGroupMute(_ group: SonosGroup) {
        let newValue = !(groupMutes[group.id] ?? false)
        groupMutes[group.id] = newValue
        Task { try? await SonosController.setGroupMute(group, muted: newValue) }
    }

    func toggleDeviceMute(_ device: SonosDevice) {
        let newValue = !(deviceMutes[device.uuid] ?? false)
        deviceMutes[device.uuid] = newValue
        Task { try? await SonosController.setMute(device, muted: newValue) }
    }

    // MARK: - Party mode

    /// Joins `device` into `target`'s group ("pair").
    func pair(_ device: SonosDevice, withGroup target: SonosGroup) {
        guard !isBusyGrouping, let coordinator = target.coordinator else { return }
        isBusyGrouping = true
        Task {
            try? await SonosController.join(device, toCoordinator: coordinator)
            try? await Task.sleep(nanoseconds: 600_000_000)
            await refreshTopologyFast()
            isBusyGrouping = false
        }
    }

    /// Removes `device` from its current group, making it standalone ("unpair").
    func unpair(_ device: SonosDevice) {
        guard !isBusyGrouping else { return }
        isBusyGrouping = true
        Task {
            try? await SonosController.unjoin(device)
            try? await Task.sleep(nanoseconds: 600_000_000)
            await refreshTopologyFast()
            isBusyGrouping = false
        }
    }

    func togglePartyMode() {
        guard !isBusyGrouping else { return }
        isBusyGrouping = true
        Task {
            if isPartyMode {
                await SonosController.ungroupAll(groups)
            } else if let coordinator = groups.first?.coordinator {
                await SonosController.partyMode(allDevices: allDevices, coordinator: coordinator)
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refreshTopologyFast()
            isBusyGrouping = false
        }
    }
}
