import SwiftUI

struct iOSContentView: View {
    @EnvironmentObject var vm: SonosViewModel
    @State private var showingLibrary = false
    @State private var showingQueue = false
    @State private var showingAlarms = false
    @State private var showingSettings = false
    @State private var showingHistory = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationTitle("Sonos Remote")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
                    ToolbarItem(placement: .navigation) {
                        Button {
                            Task { await vm.refreshTopology() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
        } detail: {
            if let group = vm.selectedGroup {
                GroupDetailView(group: group)
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            Button {
                                vm.togglePartyMode()
                            } label: {
                                Image(systemName: vm.isPartyMode ? "party.popper.fill" : "party.popper")
                            }
                            .disabled(vm.groups.count < 2 && !vm.isPartyMode)

                            Button { showingLibrary = true } label: { Image(systemName: "music.note.list") }
                            Button { showingQueue = true } label: { Image(systemName: "list.number") }
                            Button { showingAlarms = true } label: { Image(systemName: "alarm") }
                            Button { showingHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                        }
                    }
            } else if vm.isDiscovering {
                ProgressView("Looking for Sonos speakers…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Sonos speakers found",
                    systemImage: "hifispeaker.and.homepod",
                    description: Text(vm.errorMessage ?? "Make sure this device is on the same Wi-Fi network as your Sonos system.")
                )
            }
        }
        .sheet(isPresented: $showingLibrary) {
            if let group = vm.selectedGroup { LibraryView(group: group).environmentObject(vm) }
        }
        .sheet(isPresented: $showingQueue) {
            if let group = vm.selectedGroup { QueueView(group: group) }
        }
        .sheet(isPresented: $showingAlarms) {
            AlarmsView().environmentObject(vm)
        }
        .sheet(isPresented: $showingSettings) {
            iOSSettingsView()
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView().environmentObject(vm)
        }
    }
}
