import SwiftUI

/// Browses Favorites, Playlists, and the local Music Library, and plays
/// whatever's selected on the given group's coordinator. Favorites/tracks
/// play immediately; containers (playlists/albums/artists) can be drilled
/// into, or played whole via the trailing Play button.
struct LibraryView: View {
    let group: SonosGroup
    @Environment(\.dismiss) private var dismiss

    enum Root: String, CaseIterable, Identifiable {
        case favorites = "Favorites"
        case playlists = "Playlists"
        case library = "Local Library"
        var id: String { rawValue }
        var objectID: String {
            switch self {
            case .favorites: return BrowseRoot.favorites
            case .playlists: return BrowseRoot.playlists
            case .library: return BrowseRoot.musicLibraryRoot
            }
        }
    }

    @State private var root: Root = .favorites
    @State private var path: [BrowseItem] = []
    @State private var items: [BrowseItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if !path.isEmpty {
                    Button {
                        path.removeLast()
                        Task { await load() }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                Text(path.last?.title ?? root.rawValue)
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding([.horizontal, .top])

            Picker("", selection: $root) {
                ForEach(Root.allCases) { r in Text(r.rawValue).tag(r) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()
            .disabled(!path.isEmpty)
            .onChange(of: root) {
                path = []
                Task { await load() }
            }

            Divider()

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    LibraryRow(item: item, onTap: { await handleTap(item) }, onPlay: { await play(item) })
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 460, height: 560)
        .task { await load() }
    }

    private func load() async {
        guard let device = group.coordinator else { return }
        isLoading = true
        errorMessage = nil
        let objectID = path.last?.id ?? root.objectID
        do {
            items = try await SonosController.browse(device, objectID: objectID)
            if items.isEmpty { errorMessage = "Nothing here." }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func handleTap(_ item: BrowseItem) async {
        if item.isContainer {
            path.append(item)
            await load()
        } else {
            await play(item)
        }
    }

    private func play(_ item: BrowseItem) async {
        guard let device = group.coordinator else { return }
        try? await SonosController.play(item, on: device)
        dismiss()
    }
}

private struct LibraryRow: View {
    let item: BrowseItem
    let onTap: () async -> Void
    let onPlay: () async -> Void

    var body: some View {
        HStack(spacing: 10) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if item.isContainer {
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            Button {
                Task { await onPlay() }
            } label: {
                Image(systemName: "play.circle.fill")
            }
            .buttonStyle(.plain)
            .help(item.isContainer ? "Play all" : "Play")
        }
        .contentShape(Rectangle())
        .onTapGesture { Task { await onTap() } }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = item.albumArtURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                else { placeholder }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            placeholder.frame(width: 36, height: 36)
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            Image(systemName: item.isContainer ? "square.stack.fill" : "music.note")
                .foregroundStyle(.secondary)
        }
    }
}
