//
//  ForYouScreen.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import SwiftUI
import OSLog

struct ForYouScreen: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(Player.self) private var player

    @State private var isPresentingSettings = false
    @State private var selectedMedia: Media?
    @State private var playError: String?
    @State private var isRefreshing = false
    
    
    var body: some View {
        NavigationStack {
            Group {
                if !sessionManager.hasActiveSession {
                    missingProviderView
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("For You")
            .withBackgroundActivityToolbar()
            .toolbar {
                if sessionManager.hasActiveSession {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            print("TODO")
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isRefreshing)
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
                .environment(sessionManager)
            }
            #endif
            .sheet(item: $selectedMedia) { media in
                NavigationStack {
                    destination(for: media)
                }
            }
        }
    }

    @ViewBuilder
    private func content() -> some View {
//        case .failed(let error):
//            VStack(spacing: 12) {
//                Text(error.localizedDescription)
//                    .multilineTextAlignment(.center)
//                Button("Retry") {
//                    Task { await viewModel.refresh() }
//                }
//                .buttonStyle(.borderedProminent)
//            }
//            .padding()

//        case .loaded:
//            if viewModel.hero == nil && viewModel.sections.isEmpty {
//                VStack(spacing: 12) {
//                    Text("Not enough activity yet. Start watching to personalize this page.")
//                        .foregroundStyle(.secondary)
//                        .multilineTextAlignment(.center)
//                    Button("Refresh") {
////                        Task { await viewModel.refresh() }
//                    }
//                    .buttonStyle(.borderedProminent)
//                }
//                .padding()
//            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
//                        if let hero = viewModel.hero {
//                            ForYouHeroView(
//                                item: hero,
//                                onPlay: { startPlayback(video: hero.video) },
//                                onDetails: { selectedDetailVideo = hero.video }
//                            )
//                        }

                        if let playError {
                            Text(playError)
                                .foregroundStyle(.red)
                        }

//                        ForEach(viewModel.sections) { section in
//                            switch section.style {
//                            case .continueWatchingRail:
//                                continueWatchingRail(section: section)
//                            case .posterRail:
//                                ForYouRailView(section: section, destination: destination(for:))
//                            case .hero:
//                                EmptyView()
//                            }
//                        }
                    }
                    .padding()
                }
            }
//        }

//    private func continueWatchingRail() -> some View {
//        VStack(alignment: .leading, spacing: 10) {
//            Text("TODO")
//                .font(.headline)
//
//            ScrollView(.horizontal) {
//                LazyHStack(alignment: .top, spacing: 14) {
//                    ForEach(section.items) { item in
//                        NavigationLink {
//                            destination(for: item)
//                        } label: {
//                            ContinueWatchingCardView(item: item)
//                                .frame(width: 170)
//                        }
//                        .buttonStyle(.plain)
//                    }
//                }
//            }
//            .scrollIndicators(.never)
//        }
//    }

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

    @ViewBuilder
    private func destination(for media: Media) -> some View {
        switch media.self {
        case is Movie:
                MovieDetailScreen(movie: media as! Movie)
        case is Series:
                EpisodeDetailTile(series: media as! Series, episode: (media as! Series).episodes.first!)
                    .navigationTitle(media.name)
        default:
            ContentUnavailableView {
                Text("Live Episodes Are Unavailable")
            } description: {
                Text("Episode detail only applies to series content.")
            }
            .navigationTitle(media.name)
        }
    }

    private func startPlayback(media: PlayableMedia) {
        Task {
            playError = nil
            player.load(media, presentation: .fullWindow)
        }
    }
}

#Preview(traits: .previewData) {
    ForYouScreen()
}
