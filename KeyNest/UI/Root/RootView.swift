import SwiftUI
import KeyNestKit

/// Top-level shell. Switches between two navigation chrome variants based
/// on `horizontalSizeClass`:
///
/// - **Compact** (iPhone, iPad Slide Over, iPad split-screen 1/3): a plain
///   `NavigationStack`. The list pushes Edit / Settings / Danger as the
///   user drills in.
/// - **Regular** (iPad full screen, iPad split-screen 1/2 or 2/3, larger
///   iPads): a 2-column `NavigationSplitView`. The credential list lives
///   in the sidebar; Edit / Settings / Danger render in the detail pane,
///   matching Mail.app / Settings.app conventions.
///
/// `CredentialListView`'s `NavigationLink`s automatically push into the
/// detail column in the split layout — no per-view logic needed.
struct RootView: View {
    let services: ServiceLocator
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        Group {
            if hSizeClass == .regular {
                NavigationSplitView {
                    CredentialListView(services: services)
                } detail: {
                    NavigationStack {
                        EmptyDetailView()
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack {
                    CredentialListView(services: services)
                }
            }
        }
        .tint(KNColor.primary)
    }
}

/// Default detail pane shown when nothing is selected in the iPad sidebar.
/// Brand chrome + a hint that the next tap surfaces the real content.
private struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 64))
                .foregroundStyle(KNColor.text3)
            Text("Select a credential")
                .font(KNFont.title3)
                .foregroundStyle(KNColor.text)
            Text("Pick an entry from the list, or add a new one with the + button.")
                .font(KNFont.callout)
                .foregroundStyle(KNColor.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KNColor.bg)
    }
}
