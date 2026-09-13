# Sonos Remote

A native SwiftUI Mac app (Apple Silicon) for controlling your Sonos system.
No cloud, no background server — it talks directly to your speakers over
local UPnP/SOAP on port 1400, the same protocol Sonos' own apps use.

## Features

- **Auto-discovery** of every room via SSDP + `ZoneGroupTopology`.
- **Now playing**: album art, title/artist/album, transport controls, live position.
- **Party Mode**: one click groups every room together (or splits them back apart).
- **Per-room pair/unpair**: right-click any room in the sidebar to join it into
  another room's group, or split it back out on its own.
- **Volume sliders**: one general slider per room/group, plus individual sliders
  for each physical speaker when rooms are grouped.
- **Intercom**: hold a push-to-talk button (with a microphone picker if you
  have more than one input device), speak, release — your voice plays as an
  announcement on the room(s) you pick, then whatever was playing there
  resumes automatically. (Sonos has no live-mic-streaming API for third-party
  apps, so this uses record → play-announcement → restore, the same pattern
  Sonos' own voice assistants and doorbell integrations use.)
- **Menu bar tray**: a custom icon in the menu bar opens a compact popover
  listing every room with its own volume slider, play/pause, and now-playing
  track, plus a Party Mode switch — without opening the main window.
- **Settings**: light/dark/system appearance, start-at-login, live status for
  every permission the app uses (with one-click links to the right System
  Settings pane), and an About section.
- **Optional live Widget** — see below.

## Requirements

- Apple Silicon Mac, macOS 14 (Sonoma) or later
- Xcode 15+
- Same LAN as your Sonos speakers
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to (re)generate the `.xcodeproj`

## Build & run

```bash
xcodegen generate
open SonosRemote.xcodeproj
```

Then hit Run in Xcode (scheme **SonosRemote**). On first launch, macOS will ask for:
- **Local Network** access (to find and control your Sonos speakers)
- **Microphone** access (for the Intercom feature)

Grant both — the app doesn't work without them. You can review and re-open
either permission's System Settings pane at any time from Settings ▸ Permissions.

### Command line

```bash
xcodegen generate
xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemote -configuration Debug build
open "$(find ~/Library/Developer/Xcode/DerivedData -iname 'SonosRemote.app' | head -1)"
```

### Tests

```bash
xcodegen generate
xcodebuild -project SonosRemote.xcodeproj -scheme SonosRemoteTests -destination 'platform=macOS,arch=arm64' test
```

Covers the XML/SOAP parsing (including a regression test for a real bug where
`upnp:album` matched inside `upnp:albumArtURI`), zone-topology parsing against
realistic fixtures, the WAV file builder used by Intercom (covers a real crash
fix — see below), `SonosViewModel`'s pure logic, and the widget's shared-state
JSON encoding.

## Optional: live Widget

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
  App/            App entry point (main window scene, tray scene, Settings scene)
  Models/         SonosDevice, SonosGroup, TrackInfo, TransportSnapshot, AppTheme
  Networking/     SSDP discovery, raw SOAP client, XML helpers
  Services/       SonosController (all Sonos actions), LocalHTTPServer
                  (serves intercom clips), IntercomService (record/broadcast),
                  AudioDeviceManager (Core Audio input device enumeration)
  Shared/         WidgetSharedState — the App-Group-backed snapshot the main
                  app writes and the widget extension reads
  ViewModels/     SonosViewModel — polls topology/now-playing every 3s
  Views/          SwiftUI screens (main window, sidebar, tray popover, settings)
SonosWidget/      Optional WidgetKit extension (see above)
SonosRemoteTests/ Unit tests
```

`SonosController` is a stateless enum of async functions — one call per
Sonos UPnP action (Play, SetVolume, SetAVTransportURI, GetZoneGroupState,
etc.). No third-party Sonos library is used; the SOAP envelopes and XML
parsing are implemented directly against Sonos' documented local API.

Intercom flow: record from the chosen mic via `AVAudioEngine` → convert to
16-bit/44.1kHz mono PCM → build a WAV file by hand (see "Notable bugs fixed"
below) → served over a tiny local HTTP server on this Mac (`LocalHTTPServer`,
port 57123) → each target room's current track/position/URI is snapshotted →
the clip plays via `SetAVTransportURI` + `Play` → once it finishes, the
room's previous state is restored.

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

## Known limitations

- State updates are polled every 3s, not pushed via UPnP eventing (GENA) —
  good enough for a personal remote, but not instant.
- Party Mode always groups under the first-listed room's coordinator.
- The app is ad-hoc signed ("Sign to Run Locally") — fine for building and
  running on your own Mac(s), but macOS Gatekeeper will warn on a machine
  that didn't build it (right-click ▸ Open bypasses this once).

## Suggested next features

Not implemented — ideas for where this could go next:

- **Streaming service integration (Spotify / Apple Music)**: Sonos doesn't
  give third parties a way to inject an arbitrary Spotify/Apple Music stream
  directly — that requires registering as a Sonos "Music Service" partner via
  their SMAPI program. The practical near-term path is to surface whatever
  you've already linked as **Sonos Favorites** or **Playlists** (both are
  just more `ContentDirectory` browse + `AVTransport` play calls, the same
  pattern already used everywhere in `SonosController`) — that gives one-tap
  access to Spotify/Apple Music content already set up in the official Sonos
  app, no OAuth needed on our side.
- **Local music library browsing**: Sonos can browse/play a local library
  share directly from its own `ContentDirectory` service; adding `Browse`
  support to `SonosController` would let this app list and play anything
  already shared with your Sonos system (e.g. from a NAS or this Mac).
- **Queue management UI**: view/reorder/remove from the current play queue.
- **Alarms & sleep timer**: Sonos exposes both over UPnP; would fit naturally
  as another `SonosController` section plus a small Settings-adjacent screen.
- **Bass/treble/loudness (EQ) controls** per room, via `RenderingControl`.
- **Shortcuts / Siri support**: the widget's `AppIntent`s (play/pause, skip,
  volume, party mode) already exist — exposing them as a Shortcuts app
  integration is mostly just adding `AppShortcutsProvider` metadata.
- **Live updates via GENA eventing** instead of polling, for instant UI
  updates and lower network chatter.
- **iOS/iPadOS companion app**, sharing all of `Models`/`Networking`/`Services`
  unchanged since none of it is macOS-specific.
