import SwiftUI

/// Bass/treble/loudness controls for one physical speaker, via RenderingControl.
struct EQView: View {
    let device: SonosDevice
    @EnvironmentObject var vm: SonosViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var bass: Double = 0
    @State private var treble: Double = 0
    @State private var loudness = false
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 16) {
            Text("EQ — \(device.name)").font(.headline)

            if isLoading {
                ProgressView()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bass: \(Int(bass))").font(.caption)
                    Slider(value: $bass, in: -10...10, step: 1) { editing in
                        if !editing { Task { await vm.attempt("Couldn't set bass") { try await SonosController.setBass(device, to: Int(bass)) } } }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Treble: \(Int(treble))").font(.caption)
                    Slider(value: $treble, in: -10...10, step: 1) { editing in
                        if !editing { Task { await vm.attempt("Couldn't set treble") { try await SonosController.setTreble(device, to: Int(treble)) } } }
                    }
                }
                Toggle("Loudness", isOn: Binding(
                    get: { loudness },
                    set: { newValue in
                        loudness = newValue
                        Task {
                            let changed = await vm.attempt("Couldn't change loudness") {
                                try await SonosController.setLoudness(device, enabled: newValue)
                            }
                            if !changed { loudness = !newValue }
                        }
                    }
                ))
            }

            Button("Close") { dismiss() }
        }
        .padding(20)
        .frame(width: 280)
        .bannerOverlay(vm)
        .task {
            bass = Double((try? await SonosController.getBass(device)) ?? 0)
            treble = Double((try? await SonosController.getTreble(device)) ?? 0)
            loudness = (try? await SonosController.getLoudness(device)) ?? false
            isLoading = false
        }
    }
}
