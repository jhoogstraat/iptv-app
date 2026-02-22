//
//  MoviesScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI
import OSLog

enum LoadState {
    case idle
    case fetching
    case error(Error)
    case done
}

struct MoviesScreen: View {
    let contentType: XtreamContentType

    @Environment(Catalog.self) private var catalog
    @Environment(ProviderStore.self) private var providerStore

    @State private var state: LoadState = .idle
    @State private var isPresentingSettings = false
    @State private var prefetchCoordinator = StreamPrefetchCoordinator()

    init(contentType: XtreamContentType = .vod) {
        self.contentType = contentType
    }

    var body: some View {
        NavigationStack {
            Group {
                if !providerStore.hasConfiguration {
                    missingProviderView
                } else {
                    contentForState
                }
            }
            .navigationTitle(screenTitle)
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
                prefetchCoordinator.stop()
                catalog.reset()
                return
            }

            await loadCategories(force: true)
        }
        .onDisappear {
            prefetchCoordinator.stop()
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
                if categories.isEmpty {
                    VStack(spacing: 12) {
                        Text(emptyCatalogMessage)
                        Button("Refresh") {
                            Task { await loadCategories(force: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(categories) { category in
                                VideoTileRow(category: category, contentType: contentType)
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
            Text("Add your provider credentials in Settings before browsing \(screenTitle.lowercased()).")
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
            switch contentType {
            case .vod:
                try await catalog.getVodCategories(force: force)
            case .series:
                try await catalog.getSeriesCategories(force: force)
            case .live:
                break
            }
            state = .done
            prefetchCoordinator.start(categories: categories, contentType: contentType, catalog: catalog)
        } catch {
            logger.error("Failed to load \(contentType.rawValue, privacy: .public) categories: \(error.localizedDescription, privacy: .public)")
            state = .error(error)
        }
    }

    private var categories: [Category] {
        switch contentType {
        case .vod:
            catalog.vodCategories
        case .series:
            catalog.seriesCategories
        case .live:
            []
        }
    }

    private var screenTitle: String {
        switch contentType {
        case .vod:
            "Movies"
        case .series:
            "Series"
        case .live:
            "Live"
        }
    }

    private var emptyCatalogMessage: String {
        switch contentType {
        case .vod:
            "No movies were returned by the provider."
        case .series:
            "No series were returned by the provider."
        case .live:
            "No channels were returned by the provider."
        }
    }
}

#Preview(traits: .previewData, .fixedLayout(width: 1000, height: 500)) {
    MoviesScreen()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}
