import SwiftUI

/// Open-source licenses screen. Lists the third-party components KeyNest
/// ships with, with a "View source" link to each project's canonical URL
/// for the full license text. Bundled-full-text is deferred (Phase 6 can
/// vendor the OFL / MIT verbatim files once localization lands).
struct OssLicensesView: View {
    var body: some View {
        List(OssLicenses.entries) { entry in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.name)
                        .font(KNFont.headline)
                        .foregroundStyle(KNColor.text)
                    Spacer()
                    Text(entry.license)
                        .font(KNFont.caption)
                        .foregroundStyle(KNColor.text2)
                }
                Text(entry.summary)
                    .font(KNFont.callout)
                    .foregroundStyle(KNColor.text2)
                if let url = entry.url {
                    Link(destination: url) {
                        Label("View source", systemImage: "link")
                            .font(KNFont.callout)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(KNColor.bg)
        .navigationTitle("Open-Source Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}
