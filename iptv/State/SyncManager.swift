//
//  Sync.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 19.03.26.
//

import SwiftUI
import SwiftData
import OSLog

@Observable
final class SyncManager {
    let container: ModelContainer
    let provider: Provider
    let service: XtreamService
    
    init(container: ModelContainer, provider: Provider, service: XtreamService) {
        self.container = container
        self.provider = provider
        self.service = service
    }
    
    func sync() {
        Task {
            while true {
                do {
                    try await syncMovies()
                } catch {
                    logger.warning("Error syncing: \(error)")
                }
            }
        }
    }
    
    private func syncMovies() async throws {
        let categories = try await service.getCategories(of: .vod)
        
        for category in categories {
            let count = try Category.countMedia(of: category.id, on: container.mainContext)
            if count > 0 {
                logger.info("Category \(category.name) up to date with \(count) media.")
                continue
            } else {
                logger.info("Synchronizing category \(category.name)")
            }
            
            let entity = MovieCategory(remoteId: category.id, name: category.name, group: nil, movies: [])
            container.mainContext.insert(entity)
            
            let streams = try await service.getStreams(of: .vod, in: category.id)
            
            logger.info("Found \(streams.count) streams in category \(category.name)")
            for stream in streams {
                let info = try await service.getVodInfo(of: stream.id)
                
                let source = MediaSource(url: service.getPlayURL(for: stream.id, type: .vod, containerExtension: stream.containerExtension))
                let movie = Movie(name: info.info.name, plot: info.info.plot, runtime: nil, releaseDate: nil, ageRating: info.info.age, country: info.info.country, director: info.info.director, cast: info.info.cast, rating: info.info.rating, genre: info.info.genre, language: nil, sourceId: stream.id, tmdbId: stream.tmdbId, coverImageURL: URL(string: info.info.coverBig), heroImageURL: URL(string: info.info.movieImage), activity: nil, category: entity, isFavorite: false, added: .now, source: source)
                container.mainContext.insert(movie)
            }
        }
    }
}
