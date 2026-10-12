import Foundation
import WidgetKit

@MainActor
final class SonosViewModel: ObservableObject {
    /// A short message shown over the UI: an action that failed, or a brief
    /// confirmation for something with no other visible effect.
    struct Banner: Equatable {
        let text: String
        let isError: Bool
    }

    @Published var groups: [SonosGroup] = []
    @Published var deviceVolumes: [String: Int] = [:]     // device UUID -> volume
    @Published var groupVolumes: [String: Int] = [:]      // group ID -> volume
    @Published var deviceMutes: [String: Bool] = [:]       // device UUID -> muted
    @Published var deviceGenerations: [String: SonosSystemGeneration] = [:] // device UUID -> S1/S2/unknown
    @Published var deviceDescriptions: [String: SonosDeviceDescription] = [:] // device UUID -> model/inputs
    @Published var groupMutes: [String: Bool] = [:]        // group ID -> muted
    @Published var nowPlaying: [String: TrackInfo] = [:]  // group ID -> track
    @Published var transportStates: [String: TransportState] = [:]
    @Published var playModes: [String: PlayMode] = [:]     // group ID -> shuffle/repeat
    @Published var isDiscovering = false
    @Published var isBusyGrouping = false
    @Published var errorMessage: String?
    @Published var banner: Banner?
    @Published var selectedGroupID: String?
    @Published private(set) var playbackHistory: [PlaybackHistoryEntry] = []

    #if os(macOS)
    let intercom = IntercomService()
    #endif

    private var started = false
    private var pollTask: Task<Void, Never>?
    private var bannerClearTask: Task<Void, Never>?
    private var lastLoggedTrack: [String: TrackInfo] = [:] // group ID -> last track we recorded to history
    /// When each group's `positionSeconds` was read, so the progress bar can
    /// keep moving between refreshes.
    private var positionAnchors: [String: Date] = [:]
    private let defaults: UserDefaults
    private let historyFileURL: URL?
    private static let historyDefaultsKey = "playbackHistory"
    static let historyLimit = 200

    /// `defaults` is injectable so tests can use an isolated `UserDefaults`
    /// suite instead of `.standard` — sharing `.standard` across test cases
    /// caused real flakiness under parallel test execution. `historyFileURL`
    /// is nil unless the app passes one, so tests never touch the real file.
    init(defaults: UserDefaults = .standard, historyFileURL: URL? = nil) {
        self.defaults = defaults
        self.historyFileURL = historyFileURL
        playbackHistory = Self.loadHistory(from: defaults)
        if let historyFileURL, !FileManager.default.fileExists(atPath: historyFileURL.path) {
            PlaybackHistoryFile.write(playbackHistory, to: historyFileURL)
        }
    }

    // MARK: - Banner (visible failures and confirmations)

    func showError(_ what: String, _ error: Error) {
        show(Banner(text: "\(what): \(Self.describe(error))", isError: true))
    }

    func showNotice(_ text: String) {
        show(Banner(text: text, isError: false))
    }

    func dismissBanner() {
        bannerClearTask?.cancel()
        banner = nil
    }

    private func show(_ newBanner: Banner) {
        banner = newBanner
        bannerClearTask?.cancel()
        let seconds: UInt64 = newBanner.isError ? 8 : 3
        bannerClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    /// Runs something the user asked for; if it fails, says so instead of
    /// failing silently. Returns whether it succeeded.
    @discardableResult
    func attempt(_ what: String, _ work: () async throws -> Void) async -> Bool {
        do {
            try await work()
            return true
        } catch {
            showError(what, error)
            return false
        }
    }

    /// A reason a person can act on, rather than a raw SOAP fault.
    static func describe(_ error: Error) -> String {
        if let soap = error as? SOAPError {
            switch soap.code {
            case 701, 711, 712, 800: return "the speaker says that isn't possible for what's playing now"
            case 714, 715, 716: return "the speaker can't play that item"
            case .some(let code): return "the speaker refused (error \(code))"
            case .none: return soap.message
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "the speaker didn't answer"
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost:
                return "the speaker can't be reached"
            default: break
            }
        }
        return error.localizedDescription
    }

    // MARK: - Play history

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

    private func appendToHistory(_ entry: PlaybackHistoryEntry) {
        playbackHistory.insert(entry, at: 0)
        if playbackHistory.count > Self.historyLimit {
            playbackHistory.removeLast(playbackHistory.count - Self.historyLimit)
        }
        if let data = try? JSONEncoder().encode(playbackHistory) {
            defaults.set(data, forKey: Self.historyDefaultsKey)
        }
        if let historyFileURL {
            PlaybackHistoryFile.write(playbackHistory, to: historyFileURL)
        }
    }

    /// Records a history entry if the group's track actually changed since
    /// the last one we logged (avoids re-logging the same song every poll).
    func recordHistoryIfChanged(group: SonosGroup, track: TrackInfo) {
        guard !track.title.isEmpty, !LocalHTTPServer.isAnnouncementURI(track.sourceURI) else { return }
        if let last = lastLoggedTrack[group.id], last.title == track.title, last.artist == track.artist { return }
        lastLoggedTrack[group.id] = track
        appendToHistory(PlaybackHistoryEntry(
            groupName: group.name, title: track.title, artist: track.artist,
            album: track.album, service: track.service,
            uri: track.sourceURI.isEmpty ? nil : track.sourceURI
        ))
    }

    // MARK: - Library and queue

    /// Plays a Favorite/Playlist/Library item from `LibraryView` and records
    /// it to history with its exact name — the one case where we actually
    /// know the playlist, since we're the one who just told Sonos to play it.
    func playLibraryItem(_ item: BrowseItem, in group: SonosGroup) {
        guard let device = group.coordinator else { return }
        Task {
            guard await attempt("Couldn't play \(item.title)", { try await SonosController.play(item, on: device) }) else { return }
            lastLoggedTrack[group.id] = TrackInfo(title: item.title, artist: item.subtitle)
            appendToHistory(PlaybackHistoryEntry(
                groupName: group.name, title: item.title, artist: item.subtitle,
                album: "", service: MusicService.detect(from: item.uri), sourceLabel: item.title,
                uri: item.uri.isEmpty ? nil : item.uri
            ))
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refreshNowPlaying(for: group)
        }
    }

    /// Plays every file in `files` (in order) on `group`'s coordinator —
    /// "play all" for a folder from the local library ("My Mac" tab), which
    /// has no single Sonos-recognized container object to enqueue whole.
    func playLocalFiles(_ files: [BrowseItem], in group: SonosGroup) {
        guard let device = group.coordinator, !files.isEmpty else { return }
        Task {
            guard await attempt("Couldn't play those files", { try await SonosController.playQueue(files, on: device) }) else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refreshNowPlaying(for: group)
        }
    }

    /// Adds to the end of the queue without interrupting what's playing.
    func addToQueue(_ items: [BrowseItem], in group: SonosGroup) {
        guard let device = group.coordinator, !items.isEmpty else { return }
        Task {
            let label = items.count == 1 ? items[0].title : "\(items.count) tracks"
            let added = await attempt("Couldn't add \(label) to the queue") {
                for item in items { try await SonosController.addToQueue(item, on: device) }
            }
            if added { showNotice("Added \(label) to the queue") }
        }
    }

    // MARK: - Derived state

    var allDevices: [SonosDevice] { groups.flatMap(\.members) }
    var allDevicesSorted: [SonosDevice] {
        allDevices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var isPartyMode: Bool { SonosPartyMode.isOn(groups) }
    var canTogglePartyMode: Bool { SonosPartyMode.canToggle(groups) }
    var playingGroups: [SonosGroup] { groups.filter { transportStates[$0.id] == .playing } }

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

    func hasTVInput(_ device: SonosDevice) -> Bool { deviceDescriptions[device.uuid]?.hasTVInput ?? false }
    func hasLineIn(_ device: SonosDevice) -> Bool { deviceDescriptions[device.uuid]?.hasLineIn ?? false }
    var tvRooms: [SonosDevice] { allDevicesSorted.filter(hasTVInput) }

    /// Where the current track has got to *now*: the last position read from
    /// the speaker, advanced by the time since, while it is playing.
    func position(in group: SonosGroup, at now: Date = Date()) -> Int {
        guard let track = nowPlaying[group.id] else { return 0 }
        var position = track.positionSeconds
        if transportStates[group.id] == .playing, let anchor = positionAnchors[group.id] {
            position += max(0, Int(now.timeIntervalSince(anchor)))
        }
        return track.durationSeconds > 0 ? min(position, track.durationSeconds) : position
    }

    private func setNowPlaying(_ track: TrackInfo, for group: SonosGroup, readAt: Date = Date()) {
        nowPlaying[group.id] = track
        positionAnchors[group.id] = readAt
        recordHistoryIfChanged(group: group, track: track)
    }

    // MARK: - Startup and live events

    /// Starts discovery, live events and the safety-net poll. Safe to call
    /// from every window that appears; returns whether this call started it.
    @discardableResult
    func start() -> Bool {
        guard !started else { return false }
        started = true
        setUpLiveEvents()
        Task { await refreshTopology() }
        // GENA push events (see setUpLiveEvents) handle near-instant updates;
        // this poll is the safety net for anything a dropped/missed event
        // would otherwise leave stale — grouping included.
        pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self else { return }
                tick += 1
                if tick % 10 == 0 {
                    // Every 5 minutes, a full rescan: the only way to notice a
                    // speaker (or a whole household) that has been switched on.
                    await self.refreshTopology()
                    continue
                }
                let changed = await self.refreshKnownTopology()
                if !changed { await self.refreshNowPlayingAndVolumes() }
            }
        }
        return true
    }

    /// Wires GENA (UPnP eventing) push notifications straight into our
    /// published state, so changes — including ones made from the official
    /// Sonos app or a physical remote — appear immediately instead of
    /// waiting for the next poll.
    private func setUpLiveEvents() {
        let manager = GENASubscriptionManager.shared
        manager.onTransportChange = { [weak self] host, state in
            guard let self, let group = self.groups.first(where: { $0.coordinator?.host == host }) else { return }
            self.transportStates[group.id] = state
            Task { await self.refreshNowPlaying(for: group) }
        }
        manager.onVolumeChange = { [weak self] host, volume in self?.applyDeviceVolume(volume, fromHost: host) }
        manager.onMuteChange = { [weak self] host, muted in self?.applyDeviceMute(muted, fromHost: host) }
        manager.onGroupVolumeChange = { [weak self] host, volume in self?.applyGroupVolume(volume, fromCoordinatorHost: host) }
        manager.onGroupMuteChange = { [weak self] host, muted in self?.applyGroupMute(muted, fromCoordinatorHost: host) }
        manager.onPlayModeChange = { [weak self] host, mode in self?.applyPlayMode(mode, fromCoordinatorHost: host) }
        manager.onTopologyChange = { [weak self] household in
            Task { await self?.applyHouseholdTopology(household) }
        }
        manager.start()
    }

    // MARK: - Volume/mute/play mode reported by the speakers (events + poll)

    /// When the user last set each volume from this app, keyed by group ID
    /// or device UUID. For a moment afterwards that value wins over anything
    /// a speaker reported before the change landed, so a late event or poll
    /// result can't yank the slider back to where it was.
    private var localVolumeChangeAt: [String: Date] = [:]
    private static let localVolumeHold: TimeInterval = 1.5

    @discardableResult
    func noteLocalVolumeChange(for key: String) -> Date {
        let stamp = Date()
        localVolumeChangeAt[key] = stamp
        return stamp
    }

    private func isHoldingLocalVolume(_ key: String) -> Bool {
        guard let at = localVolumeChangeAt[key] else { return false }
        return Date().timeIntervalSince(at) < Self.localVolumeHold
    }

    /// One speaker's own volume. Deliberately never touches the group
    /// volume, even when the speaker is the group's coordinator: the group
    /// volume is derived from every member and arrives separately, via
    /// `applyGroupVolume`.
    func applyDeviceVolume(_ volume: Int, fromHost host: String) {
        guard let device = allDevices.first(where: { $0.host == host }),
              !isHoldingLocalVolume(device.uuid) else { return }
        deviceVolumes[device.uuid] = volume
        publishWidgetSnapshot()
    }

    func applyDeviceMute(_ muted: Bool, fromHost host: String) {
        guard let device = allDevices.first(where: { $0.host == host }) else { return }
        deviceMutes[device.uuid] = muted
    }

    func applyGroupVolume(_ volume: Int, fromCoordinatorHost host: String) {
        guard let group = groups.first(where: { $0.coordinator?.host == host }),
              !isHoldingLocalVolume(group.id) else { return }
        groupVolumes[group.id] = volume
    }

    func applyGroupMute(_ muted: Bool, fromCoordinatorHost host: String) {
        guard let group = groups.first(where: { $0.coordinator?.host == host }) else { return }
        groupMutes[group.id] = muted
    }

    func applyPlayMode(_ mode: PlayMode, fromCoordinatorHost host: String) {
        guard let group = groups.first(where: { $0.coordinator?.host == host }) else { return }
        playModes[group.id] = mode
    }

    /// Reads back the group's volume and every member's own volume and mute.
    /// A group change moves every member, and a member change moves the
    /// group, so after either one both levels need refreshing — live events
    /// normally deliver this already; this covers when they aren't arriving.
    private func refreshLevels(for group: SonosGroup) async {
        async let groupVolume = try? SonosController.groupVolume(group)
        async let groupMute = try? SonosController.isGroupMuted(group)
        let members = await withTaskGroup(of: (String, Int?, Bool?).self) { taskGroup in
            for member in group.members {
                taskGroup.addTask {
                    async let volume = try? SonosController.volume(member)
                    async let muted = try? SonosController.isMuted(member)
                    return (member.uuid, await volume, await muted)
                }
            }
            var result: [(String, Int?, Bool?)] = []
            for await item in taskGroup { result.append(item) }
            return result
        }
        if let groupVolume = await groupVolume, !isHoldingLocalVolume(group.id) {
            groupVolumes[group.id] = groupVolume
        }
        if let groupMute = await groupMute { groupMutes[group.id] = groupMute }
        for (uuid, volume, muted) in members {
            if let volume, !isHoldingLocalVolume(uuid) { deviceVolumes[uuid] = volume }
            if let muted { deviceMutes[uuid] = muted }
        }
    }

    // MARK: - Topology

    /// Full rescan: SSDP discovery, then every household's topology.
    func refreshTopology() async {
        isDiscovering = true
        let discovered = await SonosController.discoverGroups(alsoAsking: Self.bootstrapHosts(for: groups))
        isDiscovering = false
        await applyTopology(discovered, redescribeAll: true)
    }

    /// Re-reads topology from speakers we already know instead of running
    /// SSDP discovery again (which always takes 3-4 s). One known speaker per
    /// household is asked, so a second household (S1 next to S2) is kept
    /// rather than dropped. Falls back to a full rescan when nothing known
    /// answers. Returns whether the topology changed.
    @discardableResult
    func refreshKnownTopology() async -> Bool {
        let hosts = Self.bootstrapHosts(for: groups)
        guard !hosts.isEmpty else {
            await refreshTopology()
            return true
        }
        let refreshed = await SonosController.mergedTopology(fromHosts: hosts)
        guard !refreshed.isEmpty else {
            await refreshTopology()
            return true
        }
        guard !Self.sameTopology(refreshed, groups) else { return false }
        await applyTopology(refreshed, redescribeAll: false)
        return true
    }

    /// Same groups with the same members, whatever order they're listed in
    /// (different speakers list their household's groups in different orders).
    nonisolated static func sameTopology(_ a: [SonosGroup], _ b: [SonosGroup]) -> Bool {
        func normalized(_ groups: [SonosGroup]) -> Set<SonosGroup> {
            Set(groups.map { group in
                var copy = group
                copy.members.sort { $0.uuid < $1.uuid }
                return copy
            })
        }
        return normalized(a) == normalized(b)
    }

    /// Up to two speakers per household to ask for its topology — a second
    /// one in case the first has just gone offline.
    nonisolated static func bootstrapHosts(for groups: [SonosGroup]) -> [String] {
        SonosPartyMode.households(groups).flatMap { household in
            household.flatMap(\.members).sorted { $0.uuid < $1.uuid }.prefix(2).map(\.host)
        }
    }

    /// Replaces one household's groups inside `current`, keeping the other
    /// households and the household's place in the list. Matching is by
    /// shared rooms as well as by ID, so a household whose ID shifted (its
    /// lowest-UUID speaker left) doesn't leave stale copies of itself behind.
    nonisolated static func merging(_ household: [SonosGroup], into current: [SonosGroup]) -> [SonosGroup] {
        guard let householdID = household.first?.householdID else { return current }
        let incomingRooms = Set(household.flatMap(\.members).map(\.uuid))
        func belongs(_ group: SonosGroup) -> Bool {
            group.householdID == householdID || group.members.contains { incomingRooms.contains($0.uuid) }
        }
        var result = current
        if let firstIndex = result.firstIndex(where: belongs) {
            result.removeAll(where: belongs)
            result.insert(contentsOf: household, at: min(firstIndex, result.count))
        } else {
            result.append(contentsOf: household)
        }
        return result
    }

    /// A topology event for one household: fold it into what we have.
    func applyHouseholdTopology(_ household: [SonosGroup]) async {
        let merged = Self.merging(household, into: groups)
        guard !Self.sameTopology(merged, groups) else { return }
        await applyTopology(merged, redescribeAll: false)
    }

    private func applyTopology(_ discovered: [SonosGroup], redescribeAll: Bool) async {
        if discovered.isEmpty {
            errorMessage = "No Sonos speakers found on this network."
            return
        }
        errorMessage = nil
        let previouslySelectedRoom = selectedGroup?.coordinator
        groups = discovered
        if selectedGroupID == nil || !discovered.contains(where: { $0.id == selectedGroupID }) {
            // Group IDs change whenever grouping does; stay on the same room.
            let stillThere = previouslySelectedRoom.flatMap { room in discovered.first { $0.members.contains(room) } }
            selectedGroupID = (stillThere ?? discovered.first)?.id
        }
        await GENASubscriptionManager.shared.updateSubscriptions(
            coordinatorHosts: discovered.compactMap { $0.coordinator?.host },
            memberHosts: discovered.flatMap(\.members).map(\.host),
            topologyHosts: SonosPartyMode.households(discovered).compactMap { household in
                household.flatMap(\.members).min { $0.uuid < $1.uuid }?.host
            }
        )
        let devices = discovered.flatMap(\.members)
        let toDescribe = redescribeAll ? devices : devices.filter { deviceDescriptions[$0.uuid] == nil }
        async let descriptions = SonosController.describe(toDescribe)
        await refreshNowPlayingAndVolumes()
        for (uuid, description) in await descriptions {
            deviceDescriptions[uuid] = description
            deviceGenerations[uuid] = SonosGenerationDetector.detect(from: description)
        }
    }

    /// True the moment a second Sonos household — running the *other*
    /// generation — is detected on the network (Sonos explicitly supports
    /// running S1 and S2 households side by side during a phased upgrade).
    var hasMixedGenerations: Bool {
        let generations = Set(allDevices.compactMap { deviceGenerations[$0.uuid] }.filter { $0 != .unknown })
        return generations.count > 1
    }

    // MARK: - Now playing

    /// Refreshes one group's now-playing/transport/play mode — used after a
    /// GENA transport-change event or a transport action, so we don't wait
    /// for the poll to pick up the new track or position.
    private func refreshNowPlaying(for group: SonosGroup) async {
        guard let coordinator = group.coordinator else { return }
        async let track = try? SonosController.trackInfo(coordinator)
        async let state = try? SonosController.transportState(coordinator)
        async let mode = try? SonosController.playMode(coordinator)
        let readAt = Date()
        if let state = await state { transportStates[group.id] = state }
        if let track = await track { setNowPlaying(track, for: group, readAt: readAt) }
        if let mode = await mode { playModes[group.id] = mode }
        publishWidgetSnapshot()
    }

    func refreshNowPlayingAndVolumes() async {
        let current = groups
        await withTaskGroup(of: Void.self) { taskGroup in
            for group in current {
                taskGroup.addTask {
                    await self.refreshNowPlaying(for: group)
                    await self.refreshLevels(for: group)
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
            await attempt(isPlaying ? "Couldn't pause \(group.name)" : "Couldn't play in \(group.name)") {
                if isPlaying {
                    try await SonosController.pause(coordinator)
                } else {
                    try await SonosController.play(coordinator)
                }
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            await refreshNowPlaying(for: group)
        }
    }

    func next(_ group: SonosGroup) {
        guard let coordinator = group.coordinator else { return }
        Task { await attempt("Couldn't skip to the next track") { try await SonosController.next(coordinator) } }
    }

    func previous(_ group: SonosGroup) {
        guard let coordinator = group.coordinator else { return }
        Task { await attempt("Couldn't go back a track") { try await SonosController.previous(coordinator) } }
    }

    func seek(_ group: SonosGroup, toSeconds seconds: Int) {
        guard let coordinator = group.coordinator, var track = nowPlaying[group.id] else { return }
        track.positionSeconds = seconds
        nowPlaying[group.id] = track
        positionAnchors[group.id] = Date()
        Task {
            await attempt("Couldn't jump to that position") { try await SonosController.seek(coordinator, toSeconds: seconds) }
            await refreshNowPlaying(for: group)
        }
    }

    func toggleShuffle(_ group: SonosGroup) {
        var mode = playModes[group.id] ?? PlayMode()
        mode.shuffle.toggle()
        setPlayMode(mode, for: group, what: "Couldn't change shuffle")
    }

    func cycleRepeat(_ group: SonosGroup) {
        setPlayMode((playModes[group.id] ?? PlayMode()).nextRepeat, for: group, what: "Couldn't change repeat")
    }

    private func setPlayMode(_ mode: PlayMode, for group: SonosGroup, what: String) {
        guard let coordinator = group.coordinator else { return }
        let previous = playModes[group.id]
        playModes[group.id] = mode
        Task {
            let changed = await attempt(what) { try await SonosController.setPlayMode(coordinator, to: mode) }
            guard changed else {
                playModes[group.id] = previous
                return
            }
            // Some sources (a Spotify Connect session, for one) accept the
            // request and then keep their own shuffle/repeat. Show what the
            // speaker actually did rather than what was asked for.
            if let actual = try? await SonosController.playMode(coordinator), actual != mode {
                playModes[group.id] = actual
                show(Banner(text: "\(what): that's controlled from the app the music is playing from", isError: true))
            }
        }
    }

    // MARK: - Volume

    func setGroupVolume(_ group: SonosGroup, to value: Int) {
        groupVolumes[group.id] = value
        let stamp = noteLocalVolumeChange(for: group.id)
        Task {
            await attempt("Couldn't set the volume of \(group.name)") { try await SonosController.setGroupVolume(group, to: value) }
            await finishLocalVolumeChange(key: group.id, stamp: stamp, group: group)
        }
    }

    func setDeviceVolume(_ device: SonosDevice, to value: Int) {
        deviceVolumes[device.uuid] = value
        let stamp = noteLocalVolumeChange(for: device.uuid)
        Task {
            await attempt("Couldn't set the volume of \(device.name)") { try await SonosController.setVolume(device, to: value) }
            await finishLocalVolumeChange(key: device.uuid, stamp: stamp, group: group(containing: device))
        }
    }

    /// Once the speaker has the new value, release the hold and read back
    /// the real state — unless the user has already changed it again, in
    /// which case that newer change owns the hold and the read-back.
    private func finishLocalVolumeChange(key: String, stamp: Date, group: SonosGroup?) async {
        guard localVolumeChangeAt[key] == stamp else { return }
        localVolumeChangeAt[key] = nil
        if let group {
            await refreshLevels(for: group)
            publishWidgetSnapshot()
        }
    }

    func toggleGroupMute(_ group: SonosGroup) {
        let newValue = !(groupMutes[group.id] ?? false)
        groupMutes[group.id] = newValue
        Task {
            let changed = await attempt("Couldn't change mute for \(group.name)") {
                try await SonosController.setGroupMute(group, muted: newValue)
            }
            if !changed { groupMutes[group.id] = !newValue }
        }
    }

    func toggleDeviceMute(_ device: SonosDevice) {
        let newValue = !(deviceMutes[device.uuid] ?? false)
        deviceMutes[device.uuid] = newValue
        Task {
            let changed = await attempt("Couldn't change mute for \(device.name)") {
                try await SonosController.setMute(device, muted: newValue)
            }
            if !changed { deviceMutes[device.uuid] = !newValue }
        }
    }

    // MARK: - Grouping and Party Mode

    /// Joins `device` into `target`'s group ("pair").
    func pair(_ device: SonosDevice, withGroup target: SonosGroup) {
        guard !isBusyGrouping, let coordinator = target.coordinator else { return }
        isBusyGrouping = true
        Task {
            await attempt("Couldn't add \(device.name) to \(target.name)") {
                try await SonosController.join(device, toCoordinator: coordinator)
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
            await refreshKnownTopology()
            isBusyGrouping = false
        }
    }

    /// Removes `device` from its current group, making it standalone ("unpair").
    func unpair(_ device: SonosDevice) {
        guard !isBusyGrouping else { return }
        isBusyGrouping = true
        Task {
            await attempt("Couldn't ungroup \(device.name)") { try await SonosController.unjoin(device) }
            try? await Task.sleep(nanoseconds: 600_000_000)
            await refreshKnownTopology()
            isBusyGrouping = false
        }
    }

    /// Groups every household into one group each, or splits them all.
    func togglePartyMode() {
        guard !isBusyGrouping, canTogglePartyMode else { return }
        isBusyGrouping = true
        let current = groups
        let wasOn = isPartyMode
        let steps = SonosPartyMode.plan(
            current, playingGroupIDs: Set(playingGroups.map(\.id)), preferredGroupID: selectedGroup?.id
        )
        Task {
            if wasOn {
                await SonosController.ungroupAll(current)
            } else {
                for step in steps {
                    await SonosController.partyMode(allDevices: step.joiners, coordinator: step.coordinator)
                }
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refreshKnownTopology()
            if isPartyMode == wasOn {
                show(Banner(text: wasOn ? "Some rooms didn't leave the group" : "Some rooms didn't join the group", isError: true))
            }
            isBusyGrouping = false
        }
    }

    // MARK: - Inputs and routines

    func switchToTV(_ device: SonosDevice) {
        Task {
            await attempt("Couldn't switch \(device.name) to TV") { try await SonosController.switchToTV(device) }
            if let group = group(containing: device) { await refreshNowPlaying(for: group) }
        }
    }

    func switchToLineIn(_ device: SonosDevice) {
        Task {
            await attempt("Couldn't switch \(device.name) to line-in") { try await SonosController.switchToLineIn(device) }
            if let group = group(containing: device) { await refreshNowPlaying(for: group) }
        }
    }

    /// Pauses everything that is playing, in every household.
    func pauseAll() {
        let playing = playingGroups
        guard !playing.isEmpty else {
            showNotice("Nothing is playing")
            return
        }
        Task {
            var failed: [String] = []
            for group in playing {
                guard let coordinator = group.coordinator else { continue }
                do { try await SonosController.pause(coordinator) } catch { failed.append(group.name) }
            }
            if failed.isEmpty {
                showNotice(playing.count == 1 ? "Paused \(playing[0].name)" : "Paused \(playing.count) groups")
            } else {
                show(Banner(text: "Couldn't pause \(failed.joined(separator: ", "))", isError: true))
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            await refreshNowPlayingAndVolumes()
        }
    }

    /// Sets a sleep timer on everything that is playing, and lowers (never
    /// raises) any room louder than the configured ceiling.
    func goodnight(_ settings: RoutineSettings? = nil) {
        let settings = settings ?? RoutineSettings(defaults: defaults)
        let playing = playingGroups
        guard !playing.isEmpty else {
            showNotice("Nothing is playing")
            return
        }
        Task {
            let done = await attempt("Goodnight didn't finish") {
                for group in playing {
                    guard let coordinator = group.coordinator else { continue }
                    try await SonosController.setSleepTimer(coordinator, seconds: settings.goodnightMinutes * 60)
                    guard let ceiling = settings.goodnightMaxVolume else { continue }
                    for member in group.members where (deviceVolumes[member.uuid] ?? 0) > ceiling {
                        try await SonosController.setVolume(member, to: ceiling)
                    }
                }
            }
            if done { showNotice("Goodnight: music stops in \(settings.goodnightMinutes) min") }
            await refreshNowPlayingAndVolumes()
        }
    }

    /// Takes `room` out of any group, switches it to its TV input, and
    /// optionally sets its volume and pauses everything else.
    func movieNight(in room: SonosDevice, _ settings: RoutineSettings? = nil) {
        let settings = settings ?? RoutineSettings(defaults: defaults)
        let wasGrouped = (group(containing: room)?.members.count ?? 1) > 1
        Task {
            let done = await attempt("Movie night didn't finish") {
                if wasGrouped {
                    try await SonosController.unjoin(room)
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
                try await SonosController.switchToTV(room)
                if let volume = settings.movieNightVolume {
                    try await SonosController.setVolume(room, to: volume)
                }
            }
            // Leaving a group can hand it a new coordinator, so re-read who
            // leads what before pausing the others.
            try? await Task.sleep(nanoseconds: 600_000_000)
            let changed = await refreshKnownTopology()
            if !changed { await refreshNowPlayingAndVolumes() }
            guard done else { return }
            if settings.movieNightPauseOthers {
                for group in playingGroups where !group.members.contains(room) {
                    if let coordinator = group.coordinator { try? await SonosController.pause(coordinator) }
                }
                await refreshNowPlayingAndVolumes()
            }
            showNotice("Movie night: \(room.name) is on TV")
        }
    }
}
