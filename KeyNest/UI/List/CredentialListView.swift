import SwiftUI
import KeyNestKit

/// Credential list screen. Req 7.1 (Phase 3.2):
/// - `.searchable` query against label / username / serviceIdentifier
/// - sort menu (`updated-desc` / `label-asc` / `domain-asc`)
/// - recently-used carousel (top 5, independent of search)
/// - empty states: initial (vault truly empty) vs no-match (filtered to 0)
/// - swipe actions: duplicate (leading) / delete (trailing, destructive)
///
/// PassKey rows and a signature-chip filter exist in the Android port but are
/// intentionally out of scope here (design Non-Goals / future phase).
struct CredentialListView: View {
    @State private var viewModel: CredentialListViewModel
    @State private var pendingDelete: Credential?
    private let services: ServiceLocator

    init(services: ServiceLocator) {
        self.services = services
        _viewModel = State(initialValue: CredentialListViewModel(services: services))
    }

    var body: some View {
        content
            .navigationTitle("KeyNest")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbar }
            .searchable(
                text: Binding(
                    get: { viewModel.query },
                    set: viewModel.onQueryChanged
                ),
                prompt: "Search vault"
            )
            .task(id: viewModel.sort) {
                await viewModel.observeMain(sort: viewModel.sort)
            }
            .task {
                await viewModel.observeRecent()
            }
            .alert(item: $viewModel.actionMessage) { msg in
                Alert(title: Text(msg.text))
            }
            .confirmationDialog(
                "Delete credential?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                presenting: pendingDelete
            ) { credential in
                Button("Delete", role: .destructive) {
                    Task { await viewModel.delete(credential.id) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { credential in
                Text("\"\(credential.label)\" will be permanently removed.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if let kind = viewModel.emptyKind {
            EmptyStateView(kind: kind)
        } else {
            List {
                if !viewModel.recentList.isEmpty && viewModel.query.isEmpty {
                    Section("Recently used") {
                        RecentlyUsedCarousel(items: viewModel.recentList)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                Section {
                    ForEach(viewModel.filteredList) { credential in
                        NavigationLink {
                            CredentialEditView(mode: .edit(credential.id), services: services)
                        } label: {
                            CredentialRow(credential: credential)
                        }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    Task { await viewModel.duplicate(credential.id) }
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }
                                .tint(KNColor.primary)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = credential
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text("All credentials (\(viewModel.filteredList.count))")
                        .font(KNFont.footnote)
                        .foregroundStyle(KNColor.text2)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(KNColor.bg)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort by", selection: Binding(
                    get: { viewModel.sort },
                    set: viewModel.onSortChanged
                )) {
                    Text("Updated (newest)").tag(CredentialSortOrder.updatedDesc)
                    Text("Label (A→Z)").tag(CredentialSortOrder.labelAsc)
                    Text("Domain (A→Z)").tag(CredentialSortOrder.domainAsc)
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort")
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                CredentialEditView(mode: .new, services: services)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add credential")
        }
    }
}

// MARK: - Subviews

private struct CredentialRow: View {
    let credential: Credential

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(credential.label)
                .font(KNFont.headline)
                .foregroundStyle(KNColor.text)
                .lineLimit(1)
            Text(credential.username)
                .font(KNFont.callout)
                .foregroundStyle(KNColor.text2)
                .lineLimit(1)
            Text(credential.serviceIdentifier)
                .font(KNFont.caption)
                .foregroundStyle(KNColor.text3)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

private struct RecentlyUsedCarousel: View {
    let items: [Credential]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(items) { credential in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(credential.label)
                            .font(KNFont.callout)
                            .foregroundStyle(KNColor.text)
                            .lineLimit(1)
                        Text(credential.username)
                            .font(KNFont.caption)
                            .foregroundStyle(KNColor.text2)
                            .lineLimit(1)
                    }
                    .padding(12)
                    .frame(width: 180, alignment: .leading)
                    .background(KNColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(KNColor.border, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

private struct EmptyStateView: View {
    let kind: EmptyKind

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: kind == .initial ? "key.fill" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(KNColor.text3)
            Text(title)
                .font(KNFont.title3)
                .foregroundStyle(KNColor.text)
            Text(message)
                .font(KNFont.callout)
                .foregroundStyle(KNColor.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KNColor.bg)
    }

    private var title: String {
        switch kind {
        case .initial: return "Your vault is empty"
        case .noMatch: return "No matches"
        }
    }

    private var message: String {
        switch kind {
        case .initial: return "Saved credentials will appear here. Use the AutoFill flow or add one manually."
        case .noMatch: return "Try a different search term."
        }
    }
}
