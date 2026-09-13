import SwiftUI

/// View/reorder/remove tracks in the group's current play queue.
struct QueueView: View {
    let group: SonosGroup
    @Environment(\.dismiss) private var dismiss

    @State private var items: [BrowseItem] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Queue (\(items.count))").font(.headline)
                Spacer()
                Button("Clear", role: .destructive) { Task { await clearAll() } }
                    .disabled(items.isEmpty)
                Button("Close") { dismiss() }
            }
            .padding()

            Divider()

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                Text("Queue is empty.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).lineLimit(1)
                                if !item.subtitle.isEmpty {
                                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Button {
                                Task { await remove(at: index) }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { Task { await play(trackNumber: index + 1) } }
                    }
                    .onMove(perform: move)
                    .onDelete { offsets in Task { await removeAll(at: offsets) } }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 420, height: 560)
        .task { await load() }
    }

    private func load() async {
        guard let device = group.coordinator else { return }
        isLoading = true
        items = (try? await SonosController.getQueue(device)) ?? []
        isLoading = false
    }

    private func play(trackNumber: Int) async {
        guard let device = group.coordinator else { return }
        try? await SonosController.playFromQueue(device, trackNumber: trackNumber)
        dismiss()
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let device = group.coordinator, let from = source.first else { return }
        let fromTrackNumber = from + 1
        let toTrackNumber = destination + 1
        items.move(fromOffsets: source, toOffset: destination)
        Task { try? await SonosController.reorderQueue(device, fromTrackNumber: fromTrackNumber, toTrackNumber: toTrackNumber) }
    }

    private func remove(at index: Int) async {
        guard let device = group.coordinator else { return }
        items.remove(at: index)
        try? await SonosController.removeFromQueue(device, trackNumber: index + 1)
    }

    private func removeAll(at offsets: IndexSet) async {
        guard let device = group.coordinator else { return }
        let trackNumbers = offsets.map { $0 + 1 }.sorted(by: >)
        items.remove(atOffsets: offsets)
        for trackNumber in trackNumbers {
            try? await SonosController.removeFromQueue(device, trackNumber: trackNumber)
        }
    }

    private func clearAll() async {
        guard let device = group.coordinator else { return }
        try? await SonosController.clearQueue(device)
        items = []
    }
}
