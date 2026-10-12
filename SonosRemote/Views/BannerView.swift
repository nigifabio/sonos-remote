import SwiftUI

/// The strip that reports a failed action (or briefly confirms one with no
/// other visible effect). Click to dismiss; it also clears itself.
struct BannerView: View {
    let banner: SonosViewModel.Banner
    var compact = false
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(banner.isError ? Color.orange : Color.green)
                Text(banner.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(compact ? .caption2 : .callout)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 5 : 8)
            .frame(maxWidth: compact ? .infinity : 520, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        }
        .buttonStyle(.plain)
        .help("Dismiss")
        .accessibilityLabel(banner.text)
    }
}

extension View {
    /// Shows the view model's banner along the top of this view — used on
    /// the main window and on every sheet, since a sheet covers the window.
    func bannerOverlay(_ vm: SonosViewModel) -> some View {
        overlay(alignment: .top) {
            if let banner = vm.banner {
                BannerView(banner: banner, onDismiss: vm.dismissBanner)
                    .padding(.top, 6)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: vm.banner)
    }
}
