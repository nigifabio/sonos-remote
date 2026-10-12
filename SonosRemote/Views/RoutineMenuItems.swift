import SwiftUI

/// The one-tap routines, as menu items — shared by the Mac toolbar menu and
/// the iOS menu. Movie Night only appears when a room has a TV input.
struct RoutineMenuItems: View {
    @EnvironmentObject var vm: SonosViewModel

    var body: some View {
        Button {
            vm.pauseAll()
        } label: {
            Label("Pause All", systemImage: "pause.circle")
        }
        .disabled(vm.allDevices.isEmpty)

        Button {
            vm.goodnight()
        } label: {
            Label("Goodnight", systemImage: "moon.zzz")
        }
        .disabled(vm.allDevices.isEmpty)

        ForEach(vm.tvRooms) { room in
            Button {
                vm.movieNight(in: room)
            } label: {
                Label(vm.tvRooms.count > 1 ? "Movie Night — \(room.name)" : "Movie Night", systemImage: "popcorn")
            }
        }
    }
}
