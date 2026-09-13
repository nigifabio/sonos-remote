import Foundation
import WidgetKit

@MainActor
final class SonosViewModel: ObservableObject {
    @Published var groups: [SonosGroup] = []
    @Published var deviceVolumes: [String: Int] = [:]     // device UUID -> volume
    @Published var groupVolumes: [String: Int] = [:]      // group ID -> volume
    @Published var nowPlaying: [String: TrackInfo] = [:]  // group ID -> track
    @Published var transportStates: [String: TransportState] = [:]
    @Published var isDiscovering = false
    @Published var isBusyGrouping = false
    @Published var errorMessage: String?
    @Published var selectedGroupID: String?

    #if os(macOS)
    let intercom = IntercomService()
    #endif

    private var pollTask: Task<Void, Never>?

    var allDevices: [SonosDevice] { groups.flatMap(\.members) }
    var allDevicesSorted: [SonosDevice] { allDevices.sorted { $0.name < $1.name } }
    var isPartyMode: Bool { groups.count == 1 && (groups.first?.members.count ?? 0) > 1 }

    var selectedGroup: SonosGroup? {
        groups.first { $0.id == selectedGroupID } ?? groups.first
    }

    func group(containing device: SonosDevice) -> SonosGroup? {
        groups.first { $0.members.contains(device) }
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
        await refreshNowPlayingAndVolumes()
    }

    /// Refreshes just one group's now-playing/transport/volume — used after a
    /// GENA transport-change event so we don't wait for the full poll cycle
    /// just to pick up the new track's title/artist/art.
    private func refreshNowPlaying(for group: SonosGroup) async {
        guard let coordinator = group.coordinator else { return }
        if let track = try? await SonosController.trackInfo(coordinator) { nowPlaying[group.id] = track }
        if let state = try? await SonosController.transportState(coordinator) { transportStates[group.id] = state }
        publishWidgetSnapshot()
    }

    func refreshNowPlayingAndVolumes() async {
        for group in groups {
            guard let coordinator = group.coordinator else { continue }
            async let track = try? SonosController.trackInfo(coordinator)
            async let state = try? SonosController.transportState(coordinator)
            async let gVolume = try? SonosController.groupVolume(group)
            if let track = await track { nowPlaying[group.id] = track }
            if let state = await state { transportStates[group.id] = state }
            if let gVolume = await gVolume { groupVolumes[group.id] = gVolume }

            for member in group.members {
                if let vol = try? await SonosController.volume(member) {
                    deviceVolumes[member.uuid] = vol
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

    // MARK: - Party mode

    /// Joins `device` into `target`'s group ("pair").
    func pair(_ device: SonosDevice, withGroup target: SonosGroup) {
        guard !isBusyGrouping, let coordinator = target.coordinator else { return }
        isBusyGrouping = true
        Task {
            try? await SonosController.join(device, toCoordinator: coordinator)
            try? await Task.sleep(nanoseconds: 600_000_000)
            await refreshTopology()
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
            await refreshTopology()
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
            await refreshTopology()
            isBusyGrouping = false
        }
    }
}
