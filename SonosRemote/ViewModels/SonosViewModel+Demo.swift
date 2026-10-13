import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Cover art for the sample tracks: a gradient drawn at launch, so the demo
/// ships no image files and shows no real album's artwork.
private enum DemoArtwork {
    typealias RGB = (red: CGFloat, green: CGFloat, blue: CGFloat)

    static func url(named name: String, from top: RGB, to bottom: RGB) -> URL? {
        let side = 600
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [CGColor(red: top.red, green: top.green, blue: top.blue, alpha: 1),
                      CGColor(red: bottom.red, green: bottom.green, blue: bottom.blue, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: side, y: 0), options: [])
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
        context.fillEllipse(in: CGRect(x: 330, y: 300, width: 420, height: 420))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.10))
        context.fillEllipse(in: CGRect(x: -160, y: -200, width: 460, height: 460))
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
        context.setLineWidth(10)
        context.setLineCap(.round)
        for row in 0..<3 {
            let y = CGFloat(260 + row * 40)
            context.move(to: CGPoint(x: 230, y: y))
            context.addCurve(to: CGPoint(x: 370, y: y), control1: CGPoint(x: 265, y: y + 34), control2: CGPoint(x: 335, y: y - 34))
            context.strokePath()
        }
        guard let image = context.makeImage() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sonos-remote-demo-\(name).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? url : nil
    }
}

/// A built-in sample household, for looking around the app with no Sonos
/// system on the network and for taking screenshots that show nobody's
/// real rooms. Start the app with `--demo` to use it.
extension SonosViewModel {
    static var isDemoRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo")
    }

    /// The view model the app should run with: the demo one when asked for
    /// on the command line, otherwise a normal one.
    static func forLaunch(historyFileURL: URL? = nil) -> SonosViewModel {
        isDemoRequested ? demo() : SonosViewModel(historyFileURL: historyFileURL)
    }

    static func demo() -> SonosViewModel {
        let albumArt = [
            "Slow Coastline": DemoArtwork.url(named: "coast", from: (0.10, 0.46, 0.62), to: (0.98, 0.62, 0.36)),
            "Night Drive": DemoArtwork.url(named: "night", from: (0.20, 0.16, 0.42), to: (0.72, 0.28, 0.52))
        ]
        // Its own defaults suite, emptied each time, so demo plays never mix
        // with the real play history.
        let suite = "com.fabionigi.SonosRemote.demo"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let viewModel = SonosViewModel(defaults: UserDefaults(suiteName: suite) ?? .standard)

        func room(_ id: String, _ name: String, _ lastOctet: Int) -> SonosDevice {
            SonosDevice(uuid: "RINCON_DEMO_\(id)", name: name, host: "192.0.2.\(lastOctet)")
        }
        let living = room("1", "Living Room", 11)
        let kitchen = room("2", "Kitchen", 12)
        let office = room("3", "Office", 13)
        let bedroom = room("4", "Bedroom", 14)
        let patio = room("5", "Patio", 15)
        let garage = room("9", "Garage", 19)

        let main = SonosGroup(id: "demo-main", coordinatorUUID: living.uuid, members: [living, kitchen, office], householdID: "demo-s2")
        let night = SonosGroup(id: "demo-bedroom", coordinatorUUID: bedroom.uuid, members: [bedroom], householdID: "demo-s2")
        let outside = SonosGroup(id: "demo-patio", coordinatorUUID: patio.uuid, members: [patio], householdID: "demo-s2")
        let legacy = SonosGroup(id: "demo-garage", coordinatorUUID: garage.uuid, members: [garage], householdID: "demo-s1")

        func track(_ title: String, _ artist: String, _ album: String, duration: Int, position: Int, uri: String) -> TrackInfo {
            TrackInfo(title: title, artist: artist, album: album, albumArtURL: albumArt[title] ?? nil,
                      durationSeconds: duration, positionSeconds: position, sourceURI: uri)
        }
        let earlier = track("Paper Lanterns", "Halden & Reed", "Small Hours", duration: 201, position: 0, uri: "x-sonos-spotify:demo3")
        let nightTrack = track("Night Drive", "Halden & Reed", "Small Hours", duration: 248, position: 131, uri: "x-sonos-spotify:demo2")
        let mainTrack = track("Slow Coastline", "Northern Rooms", "Tidewater", duration: 215, position: 84, uri: "x-sonos-spotify:demo1")

        viewModel.installDemoState(
            groups: [main, night, outside, legacy],
            tracks: [main.id: mainTrack, night.id: nightTrack],
            states: [main.id: .playing, night.id: .paused, outside.id: .stopped, legacy.id: .stopped],
            modes: [main.id: PlayMode(shuffle: true, repeatMode: .all)],
            groupVolumes: [main.id: 32, night.id: 18, outside.id: 25, legacy.id: 20],
            deviceVolumes: [living.uuid: 38, kitchen.uuid: 30, office.uuid: 28, bedroom.uuid: 18, patio.uuid: 25, garage.uuid: 20],
            descriptions: [
                living.uuid: SonosDeviceDescription(modelName: "Sonos Beam", modelNumber: "S14", displayVersion: "18.8", hasTVInput: true),
                kitchen.uuid: SonosDeviceDescription(modelName: "Sonos One", modelNumber: "S18", displayVersion: "18.8"),
                office.uuid: SonosDeviceDescription(modelName: "Sonos Era 300", modelNumber: "S41", displayVersion: "18.8", hasLineIn: true),
                bedroom.uuid: SonosDeviceDescription(modelName: "Sonos One", modelNumber: "S18", displayVersion: "18.8"),
                patio.uuid: SonosDeviceDescription(modelName: "Sonos Roam", modelNumber: "S27", displayVersion: "18.8"),
                garage.uuid: SonosDeviceDescription(modelName: "Sonos Play:5", modelNumber: "S5", displayVersion: "11.16", hasLineIn: true)
            ]
        )
        // Oldest first, so the main room's track ends up "last played".
        viewModel.recordHistoryIfChanged(group: night, track: earlier)
        viewModel.recordHistoryIfChanged(group: night, track: nightTrack)
        viewModel.recordHistoryIfChanged(group: main, track: mainTrack)
        return viewModel
    }

    /// Sample content for the Library browser in demo mode. `root` is the
    /// tab's title; `container` the item drilled into, if any.
    func demoLibraryItems(root: String, container: BrowseItem?) -> [BrowseItem] {
        func item(_ title: String, _ subtitle: String = "", isFolder: Bool = false) -> BrowseItem {
            BrowseItem(id: "demo:\(root):\(title)", parentID: container?.id ?? "demo-root",
                       title: title, subtitle: subtitle, uri: "x-demo:\(title)", metadata: "", albumArtURL: nil, isContainer: isFolder)
        }
        if container != nil {
            return [item("Slow Coastline", "Northern Rooms"), item("Harbour Lights", "Northern Rooms"),
                    item("Tidewater", "Northern Rooms"), item("Salt & Pine", "Northern Rooms")]
        }
        switch root {
        case "Favorites":
            return [item("Morning Coffee", "Spotify playlist"), item("Tidewater", "Northern Rooms · album"),
                    item("Radio Paradiso", "Internet radio"), item("Small Hours", "Halden & Reed · album"),
                    item("Sunday Kitchen", "Apple Music playlist")]
        case "Playlists":
            return [item("Dinner Party", isFolder: true), item("Focus", isFolder: true), item("Road Trip", isFolder: true)]
        default:
            return [item("Artists", isFolder: true), item("Albums", isFolder: true),
                    item("Genres", isFolder: true), item("Tracks", isFolder: true)]
        }
    }

    var demoQueue: [BrowseItem] {
        [("Slow Coastline", "Northern Rooms"), ("Harbour Lights", "Northern Rooms"), ("Night Drive", "Halden & Reed"),
         ("Paper Lanterns", "Halden & Reed"), ("Salt & Pine", "Northern Rooms"), ("Tidewater", "Northern Rooms")]
            .enumerated().map { index, entry in
                BrowseItem(id: "Q:0/\(index + 1)", parentID: "Q:0", title: entry.0, subtitle: entry.1,
                           uri: "x-demo:\(entry.0)", metadata: "", albumArtURL: nil, isContainer: false)
            }
    }
}
