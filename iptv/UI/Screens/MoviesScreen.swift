//
//  MoviesScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI

enum LoadState {
    case idle
    case fetching
    case error(Error)
    case done
}

struct MoviesScreen: View {
    @Environment(Catalog.self) private var catalog
    @Environment(ProviderStore.self) private var providerStore

    @State private var state: LoadState = .idle
    @State private var isPresentingSettings = false
    
    var body: some View {
        NavigationStack {
            Group {
                if !providerStore.hasConfiguration {
                    missingProviderView
                } else {
                    contentForState
                }
            }
            .navigationTitle("Movies")
            .sheet(isPresented: $isPresentingSettings) {
                NavigationStack {
                    SettingsScreen()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    isPresentingSettings = false
                                }
                            }
                        }
                }
                .environment(providerStore)
            }
        }
        .task(id: providerStore.revision) {
            guard providerStore.hasConfiguration else {
                state = .idle
                catalog.reset()
                return
            }

            await loadCategories(force: true)
        }
    }

    @ViewBuilder
    private var contentForState: some View {
        switch state {
            case .idle, .fetching:
                ProgressView()
                    
            case .error(let error):
                VStack(spacing: 12) {
                Text(error.localizedDescription)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadCategories(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                    
            case .done:
                if catalog.vodCategories.isEmpty {
                    VStack(spacing: 12) {
                        Text("No movies were returned by the provider.")
                        Button("Refresh") {
                            Task { await loadCategories(force: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(catalog.vodCategories) { category in
                                VideoTileRow(category: category)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .toolbar(.hidden)
                }
        }
    }

    private var missingProviderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.horizontal.fill")
                .font(.largeTitle)
            Text("Configure Provider")
                .font(.title3.weight(.semibold))
            Text("Add your provider credentials in Settings before browsing movies.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Configure Provider") {
                isPresentingSettings = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadCategories(force: Bool = false) async {
        do {
            state = .fetching
            try await catalog.getVodCategories(force: force)
            state = .done
        } catch {
            logger.error("Failed to load movie categories: \(error.localizedDescription, privacy: .public)")
            state = .error(error)
        }
    }
}

#Preview(traits: .previewData, .fixedLayout(width: 1000, height: 500)) {
    MoviesScreen()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}
