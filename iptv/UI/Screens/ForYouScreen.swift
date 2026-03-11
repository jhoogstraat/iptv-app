//
//  ForYouScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI
import OSLog

struct ForYouScreen: View {
    @Environment(Catalog.self) private var catalog
    @Environment(DownloadCenter.self) private var downloadCenter
    @Environment(ProviderStore.self) private var providerStore
    @Environment(Player.self) private var player

    @State private var viewModel: ForYouViewModel?
    @State private var isPresentingSettings = false
    @State private var selectedDetailVideo: Video?
    @State private var playError: String?

    var body: some View {
        NavigationStack {
            Group {
                if !providerStore.hasConfiguration {
                    missingProviderView
                } else if let viewModel {
                    content(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("For You")
            .toolbar {
                if providerStore.hasConfiguration {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await viewModel?.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            #if !os(macOS)
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
            #endif
            .sheet(item: $selectedDetailVideo) { video in
                NavigationStack {
                    destination(for: video)
                }
            }
        }
        .task(id: providerStore.revision) {
            ensureViewModel()

            guard providerStore.hasConfiguration else {
                await MainActor.run {
                    viewModel?.phase = .idle
                    viewModel?.hero = nil
                    viewModel?.sections = []
                }
                return
            }

            await viewModel?.load(policy: .cachedThenRefresh)
        }
    }

    @ViewBuilder
    private func content(_ viewModel: ForYouViewModel) -> some View {
        switch viewModel.phase {
        case .idle, .loading:
            ProgressView()

        case .failed(let error):
            VStack(spacing: 12) {
                Text(error.localizedDescription)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

        case .loaded:
            if viewModel.hero == nil && viewModel.sections.isEmpty {
                VStack(spacing: 12) {
                    Text("Not enough activity yet. Start watching to personalize this page.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Refresh") {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if let hero = viewModel.hero {
                            ForYouHeroView(
                                item: hero,
                                onPlay: { startPlayback(video: hero.video) },
                                onDetails: { selectedDetailVideo = hero.video }
                            )
                        }

                        if let playError {
                            Text(playError)
                                .foregroundStyle(.red)
                        }

                        ForEach(viewModel.sections) { section in
                            switch section.style {
                            case .continueWatchingRail:
                                continueWatchingRail(section: section)
                            case .posterRail:
                                ForYouRailView(section: section, destination: destination(for:))
                            case .hero:
                                EmptyView()
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func continueWatchingRail(section: ForYouSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.headline)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(section.items) { item in
                        NavigationLink {
                            destination(for: item)
                        } label: {
                            ContinueWatchingCardView(item: item)
                                .frame(width: 170)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private var missingProviderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.horizontal.fill")
                .font(.largeTitle)
            Text("Configure Provider")
                .font(.title3.weight(.semibold))
            Text("Add your provider credentials in Settings before opening your personalized recommendations.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            #if os(macOS)
            SettingsLink {
                Text("Configure Provider")
            }
                .buttonStyle(.borderedProminent)
            #else
            Button("Configure Provider") {
                isPresentingSettings = true
            }
            .buttonStyle(.borderedProminent)
            #endif
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ensureViewModel() {
        if viewModel == nil {
            viewModel = ForYouViewModel(
                catalog: catalog,
                providerStore: providerStore,
                watchActivityStore: DiskWatchActivityStore.shared,
                recommendationProvider: LocalRecommendationProvider()
            )
        }
    }

    @ViewBuilder
    private func destination(for item: ForYouItem) -> some View {
        destination(for: item.video)
    }

    private func destination(for video: Video) -> AnyView {
        switch video.xtreamContentType {
        case .vod:
            AnyView(MovieDetailScreen(video: video))
        case .series:
            AnyView(
                EpisodeDetailTile(video: video)
                    .navigationTitle(video.name)
            )
        case .live:
            AnyView(
                ScopedPlaceholderView(
                    title: "Live Episodes Are Unavailable",
                    message: "Episode detail only applies to series content."
                )
                .navigationTitle(video.name)
            )
        }
    }

    private func startPlayback(video: Video) {
        Task {
            do {
                let source = try await downloadCenter.playbackSource(for: video)
                playError = nil
                player.load(video, source, presentation: .fullWindow)
            } catch {
                playError = error.localizedDescription
                logger.error("Failed to resolve playback URL for \(video.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

#Preview(traits: .previewData) {
    ForYouScreen()
}
