import SwiftUI
import KeyNestKit

/// Credential picker shown inside the AutoFill extension. Surfaces matches
/// first; falls back to the full vault below a divider so the user can
/// always recover when the OS's service identifier missed.
struct AutoFillPickerView: View {
    let matches: [Credential]
    let all: [Credential]
    let suggestedServiceIdentifier: String
    let onSelect: (Credential) -> Void
    let onSaveNew: () -> Void
    let onCancel: () -> Void

    @State private var query: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onSaveNew) {
                        Label(
                            suggestedServiceIdentifier.isEmpty
                                ? "Save new credential"
                                : "Save new for \(suggestedServiceIdentifier)",
                            systemImage: "plus.circle.fill"
                        )
                    }
                }
                if !matches.isEmpty {
                    Section {
                        ForEach(matches) { credential in
                            row(credential)
                        }
                    } header: {
                        Text("Suggested for this site")
                    }
                }
                Section {
                    ForEach(filteredOthers) { credential in
                        row(credential)
                    }
                } header: {
                    Text(matches.isEmpty ? "All credentials" : "Other credentials")
                } footer: {
                    if filteredOthers.isEmpty && matches.isEmpty {
                        Text("Your vault is empty. Add a credential in KeyNest, then try again.")
                    }
                }
            }
            .navigationTitle("KeyNest")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search vault")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private var filteredOthers: [Credential] {
        let matchIds = Set(matches.map(\.id))
        let others = all.filter { !matchIds.contains($0.id) }
        return CredentialListViewModelSearch.applySearch(others, query: query)
    }

    @ViewBuilder
    private func row(_ credential: Credential) -> some View {
        Button {
            onSelect(credential)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(credential.label).font(.headline)
                Text(credential.username).font(.subheadline).foregroundStyle(.secondary)
                Text(credential.serviceIdentifier).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    /// UIKit shim so `prepareCredentialList` can hand the host VC's view to the
    /// SwiftUI layer without leaking the controller back in. Used purely to
    /// keep the background tinted while the hosting controller lays out.
    func assignBackground(view: UIView) {
        view.backgroundColor = .systemBackground
    }
}

/// Search helper specific to the AutoFill extension; mirrors
/// `CredentialListViewModel.applySearch` since the extension target does not
/// link the host app's UI module.
private enum CredentialListViewModelSearch {
    static func applySearch(_ list: [Credential], query: String) -> [Credential] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return list }
        return list.filter {
            $0.label.lowercased().contains(needle)
                || $0.username.lowercased().contains(needle)
                || $0.serviceIdentifier.lowercased().contains(needle)
        }
    }
}
