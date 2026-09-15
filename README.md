# Sonos Remote

A native SwiftUI app for controlling your Sonos system — a Mac app (Apple
Silicon) plus an iOS/iPadOS companion. No cloud, no background server: it
talks directly to your speakers over local UPnP/SOAP on port 1400, the same
protocol Sonos' own apps use, and gets instant state updates via UPnP
eventing (GENA) instead of just polling.

## Features

- **Auto-discovery** of every room via SSDP + `ZoneGroupTopology`.
- **Live updates via GENA eventing**: subscribes to each room's AVTransport
  and RenderingControl events, so play/pause/volume changes — including ones
  made from the official Sonos app or a physical remote — appear instantly.
  A 30s poll remains as a safety net for anything a dropped event would
  otherwise leave stale.
- **Now playing**: album art, title/artist/album, transport controls, live position.
- **Favorites, Playlists & local Music Library**: browse everything you've
  already set up in the official Sonos app — including Spotify/Apple Music
  content added as a Favorite or Playlist — and play it with one tap. Sonos
  doesn't let third parties inject an arbitrary streaming service directly
  (that needs their SMAPI partner program), but Favorites/Playlists are just
  more `ContentDirectory` Browse + `AVTransport` Play calls, so this gives
  one-tap access with no OAuth needed on our side.
- **Queue management**: view, reorder (drag), remove, and jump to any track
  in the current play queue.
- **Alarms & sleep timer**: list/create/enable/delete alarms (ring with the
  built-in Sonos chime), and set a per-room sleep timer.
- **Bass/treble/loudness (EQ)** controls per physical speaker.
- **Party Mode**: one click groups every room together (or splits them back apart).
- **Per-room pair/unpair**: right-click any room in the sidebar to join it into
  another room's group, or split it back out on its own.
- **Volume sliders**: one general slider per room/group, plus individual sliders
  for each physical speaker when rooms are grouped.
- **Intercom** (Mac only): hold a push-to-talk button (with a microphone
  picker if you have more than one input device), speak, release — your
  voice plays as an announcement on the room(s) you pick, then whatever was
  playing there resumes automatically. Sonos has no live-mic-streaming API
  for third-party apps, so this uses record → play-announcement → restore,
  the same pattern Sonos' own voice assistants and doorbell integrations use.
- **Shortcuts / Siri support**: play/pause a room, skip, set volume, and
  toggle Party Mode are all exposed as `AppIntent`s with Siri phrases — ask
  Siri or build a Shortcuts automation without opening the app.
- **Menu bar tray** (Mac only): a custom icon in the menu bar opens a compact
  popover listing every room with its own volume slider, play/pause, and
  now-playing track, plus a Party Mode switch — without opening the main window.
- **Settings**: light/dark/system appearance, start-at-login, live status for
  every permission the app uses (with one-click links to the right System
  Settings pane), and an About section.
- **Optional live Widget** (Mac only) — see below.

## Platforms

- **Mac** (`SonosRemote` scheme): full feature set, Apple Silicon, macOS 14+.
- **iOS/iPadOS** (`SonosRemoteiOS` scheme): everything above except the menu
  bar tray, the widget, and Intercom (which needs the Mac-only Core Audio
  input-device picker) — that's a documented gap, not a protocol limitation;
  see "Suggested next features" below.

Both targets share `Models`, `Networking`, `Services`, and `ViewModels`
unchanged — none of it depends on AppKit or Core Audio, so the same
discovery/SOAP/GENA code and the same `SonosViewModel` run on both platforms.

## Requirements

- Apple Silicon Mac, macOS 14 (Sonoma) or later, for the Mac app
- iOS/iPadOS 17+ device or simulator, for the companion app
- Xcode 15+
- Same LAN/Wi-Fi as your Sonos speakers
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to (re)generate the `.xcodeproj`
- Works with both **Sonos S2** and **Sonos S1** (legacy) systems — see below

## Build & run

```bash
xcodegen generate
open SonosRemote.xcodeproj
```

Then hit Run in Xcode with the **SonosRemote** (Mac) or **SonosRemoteiOS**
scheme. On first launch, the OS will ask for:
- **Local Network** access (to find and control your Sonos speakers)
- **Microphone** access (Mac only, for the Intercom feature)

Grant both — the app doesn't work without Local Network access. On Mac you
can review and re-open either permission's System Settings pane at any time
from Settings ▸ Permissions.

### Command line

```bash
xcodegen generate
xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemote -configuration Debug build
open "$(find ~/Library/Developer/Xcode/DerivedData -iname 'SonosRemote.app' | head -1)"
```

For iOS, build against the simulator SDK (downloads the iOS platform via
Xcode ▸ Settings ▸ Components the first time, if you haven't already):

```bash
xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemoteiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### Tests

```bash
xcodegen generate
xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemoteTests -destination 'platform=macOS,arch=arm64' test
```

Covers XML/SOAP/DIDL parsing (including regression tests for two real bugs —
see below), zone-topology parsing against realistic fixtures, the WAV file
builder used by Intercom, GENA event parsing (`LastChange` → transport
state/volume), `SonosViewModel`'s pure logic, and the widget's shared-state
JSON encoding.

## Optional: live Widget (Mac)

`SonosWidget/` is a WidgetKit extension you can add to Notification Center /
the desktop: pick a room per widget instance, see its now-playing track, and
control play/pause, skip, volume, and Party Mode without opening the app.

Widget extensions are **always sandboxed** by Apple, with no exception, and
sharing live data between the sandboxed widget and the unsandboxed main app
requires an **App Group** — which in turn requires the project be signed with
a real Apple ID team (a free personal team is enough, no paid membership
needed). Because of that, the widget target is **not** part of the default
build or a dependency of the main app, so its absence never blocks anything
else in this project.

To enable it:

1. Open `SonosRemote.xcodeproj` in Xcode.
2. Xcode ▸ Settings ▸ Accounts ▸ "+" ▸ add your Apple ID (free tier is fine).
3. Select the **SonosRemote** target ▸ Signing & Capabilities ▸ pick your team.
4. Select the **SonosWidgetExtension** target ▸ Signing & Capabilities ▸ pick
   the same team.
5. On the **SonosRemote** target, add the **App Groups** capability with
   group `group.com.fabionigi.SonosRemote` (Xcode registers it with your
   account automatically); do the same on **SonosWidgetExtension**.
6. Make **SonosRemote** embed **SonosWidgetExtension** (Build Phases ▸ Embed
   Foundation Extensions, or ask this project's assistant to wire the
   `dependencies:`/`embed: true` line back into `project.yml`).
7. Build & run, then add the widget from System Settings ▸ Desktop & Dock (or
   Notification Center, depending on your macOS version) ▸ Edit Widgets.

## Architecture

```
SonosRemote/
  App/            Mac app entry point (main window scene, tray scene, Settings scene)
  Shortcuts/      Siri/Shortcuts AppIntents + AppShortcutsProvider (Mac; do live discovery)
  Models/         SonosDevice, SonosGroup, TrackInfo, BrowseItem, SonosAlarm, AppTheme...
  Networking/     SSDP discovery, raw SOAP client, XML/DIDL parsing
  Services/       SonosController (all Sonos actions incl. Browse/Queue/Alarms/EQ),
                  LocalHTTPServer (serves intercom clips), GENAEventServer +
                  GENASubscriptionManager (UPnP push eventing), IntercomService,
                  AudioDeviceManager (Mac-only: Core Audio input device enumeration)
  Shared/         WidgetSharedState — the App-Group-backed snapshot the main
                  app writes and the widget extension reads
  ViewModels/     SonosViewModel — GENA-driven with a 30s poll fallback
  Views/          SwiftUI screens shared by both platforms (sidebar, now-playing,
                  Library, Queue, Alarms, EQ), plus Mac-only ones (tray, Settings, Intercom)
SonosRemoteiOS/   iOS/iPadOS app entry point + iOS-specific root/settings views
SonosWidget/      Optional Mac WidgetKit extension (see above)
SonosRemoteTests/ Unit tests
```

`SonosController` is a stateless enum of async functions — one call per
Sonos UPnP action (Play, SetVolume, SetAVTransportURI, Browse, ListAlarms,
ConfigureSleepTimer, SetBass, etc.) across AVTransport, RenderingControl,
GroupRenderingControl, ZoneGroupTopology, ContentDirectory, and AlarmClock.
No third-party Sonos library is used; every SOAP envelope and XML/DIDL
response is parsed directly against Sonos' documented local API.

**Favorites/Playlists/Library playback** (`SonosController.play(_:on:)`):
Favorites carry a self-contained, directly playable URI+metadata, so they
just go straight into `SetAVTransportURI` + `Play`. Playlists and local
Music Library containers (albums, artists) are played by replacing the
queue — `RemoveAllTracksFromQueue` + `AddURIToQueue` with the container's
own URI (Sonos expands it into individual tracks) + `SetAVTransportURI`
pointed at the queue — the same mechanism Sonos' own apps use.

**Live updates**: `GENASubscriptionManager` SUBSCRIBEs to each group
coordinator's AVTransport/RenderingControl event URLs with a CALLBACK
pointing at `GENAEventServer` (a tiny local HTTP server), renews before the
5-minute timeout, and parses each NOTIFY's `LastChange` payload into a plain
transport-state or volume change that `SonosViewModel` applies immediately.

**Intercom flow** (Mac only): record from the chosen mic via `AVAudioEngine`
→ convert to 16-bit/44.1kHz mono PCM → build a WAV file by hand (see
"Notable bugs fixed" below) → served over `LocalHTTPServer` (port 57123) →
each target room's current track/position/URI is snapshotted → the clip
plays via `SetAVTransportURI` + `Play` → once it finishes, the room's
previous state is restored.

## Notable bugs fixed along the way

- **`upnp:album` matching inside `upnp:albumArtURI`**: the tag-extraction
  regex lacked a word boundary after the tag name, so a track's album field
  came back corrupted with the album art URL and surrounding XML. Fixed by
  anchoring with `\b`; covered by a regression test.
- **Intercom crash (`EXC_BREAKPOINT` in Core Audio)**: writing an already-
  converted Int16 PCM buffer into an `AVAudioFile` opened with Int16 settings
  crashed, because `AVAudioFile.write(from:)` requires the buffer to match
  the file's *processing* format, which for PCM is always float32 regardless
  of the on-disk settings requested. Fixed by building the WAV file by hand
  (RIFF header + raw PCM bytes) instead of going through `AVAudioFile` at all.
- **Accidental deletion of `SOAPClient`**: an edit meant to add two new
  `SonosService` cases briefly overwrote the whole file, dropping the actual
  `SOAPClient.call` implementation. Caught immediately by a standalone
  compile check before it reached the app — a reminder to always rebuild
  after editing a file that's this central.

## Sonos S1 (legacy) compatibility

Sonos splits its ecosystem into **S2** (current) and **S1** (older hardware
that never upgraded). This app talks only to the local UPnP services that
have been part of Sonos' local control API since long before that split —
`AVTransport`, `RenderingControl`, `GroupRenderingControl`,
`ZoneGroupTopology`, `ContentDirectory`, and `AlarmClock` — so it should work
against an S1 household without any protocol-level changes. Concretely:

- `parseZoneGroups` filters out `IsZoneBridge="1"` members, not just
  `Invisible="1"` ones — a **Sonos Bridge** (needed on many original SonosNet
  setups, common in S1-era systems) shows up in topology but has no
  transport/rendering services, so it must never be treated as a room.
- Every SOAP call site already degrades gracefully (`try?`, default values)
  rather than crashing if an older device lacks a particular action.
- `GENASubscriptionManager` now reads back the GENA `TIMEOUT` header a
  device actually grants instead of assuming our requested 300s was
  honored, and schedules renewal off that real value. Older/embedded
  firmware is more likely to grant a shorter subscription than a current
  S2 speaker — assuming 300s regardless would let the subscription lapse
  silently, with no symptom beyond live updates quietly reverting to the
  30s poll. Verified live against real (S2) hardware, which does grant
  the full 300s requested — the fix is defensive for whatever an S1 device
  actually grants, since I have none to test against directly.

This hasn't been verified against real S1 hardware — the reference system
used throughout development is all S2 (Era 100/300, Roam). If you hit an S1
device that doesn't behave as expected, that's the gap to close next.

## Known limitations

- Party Mode always groups under the first-listed room's coordinator.
- The app is ad-hoc signed ("Sign to Run Locally") — fine for building and
  running on your own devices, but Gatekeeper will warn on a Mac that didn't
  build it (right-click ▸ Open bypasses this once), and the iOS app can only
  run on devices you've registered for local development.
- GENA subscriptions cover the group coordinator's AVTransport and
  RenderingControl only; per-satellite-speaker volume and topology changes
  (a room joining/leaving a group) are still picked up by the 30s poll, not
  pushed instantly.

## Suggested next features

- **Intercom on iOS**: needs an iOS-appropriate input picker (iOS doesn't
  have Core Audio's HAL device model — it's `AVAudioSession` route picking
  instead), so this is a real platform difference, not just missing UI.
- **GENA for `ZoneGroupTopology`**: subscribing to topology change events
  would make room grouping/ungrouping (including from the official app)
  reflect instantly instead of waiting for the 30s poll.
- **Drag-and-drop room grouping UI**, as an alternative to the context menu.
- **watchOS complication / CarPlay** for the most common controls.
- **Notarized, signed distribution** (currently ad-hoc only) — needs a paid
  Apple Developer Program membership to notarize the `.pkg` for Gatekeeper.
