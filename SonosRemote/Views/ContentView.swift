import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: SonosViewModel
    @State private var showingIntercom = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let group = vm.selectedGroup {
                GroupDetailView(group: group)
            } else if vm.isDiscovering {
                ProgressView("Looking for Sonos speakers…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Sonos speakers found",
                    systemImage: "hifispeaker.and.homepod",
                    description: Text(vm.errorMessage ?? "Make sure this Mac is on the same network as your Sonos system.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await vm.refreshTopology() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Rescan for Sonos speakers")

                Button {
                    vm.togglePartyMode()
                } label: {
                    Label("Party Mode", systemImage: vm.isPartyMode ? "party.popper.fill" : "party.popper")
                }
                .disabled(vm.groups.count < 2 && !vm.isPartyMode)
                .help(vm.isPartyMode ? "Split rooms back apart" : "Group every room together")

                Button {
                    showingIntercom = true
                } label: {
                    Label("Intercom", systemImage: "mic.circle.fill")
                }
                .help("Speak an announcement to one or more rooms")

                SettingsLink {
                    Label("Settings", systemImage: "gear")
                }
                .help("Settings")
            }
        }
        .sheet(isPresented: $showingIntercom) {
            IntercomView(intercom: vm.intercom)
                .environmentObject(vm)
        }
        .overlay(alignment: .top) {
            if let error = vm.errorMessage, !vm.groups.isEmpty {
                Text(error)
                    .font(.caption)
                    .padding(6)
                    .background(.yellow.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 4)
            }
        }
    }
}
