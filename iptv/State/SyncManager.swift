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
    private let container: ModelContainer
    private let provider: Provider
    private let service: XtreamService
    
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
    
    private func fullIndex() async throws {
        let categories = try await service.getCategories(of: .vod)
        let streams = try await service.getStreams(of: .vod)
        
        let movieCategories = categories.map(MovieCategory.init)
        
        for stream in streams {
            
        }
    }
    
    private func syncMovies() async throws {
        for category in try await service.getCategories(of: .vod) {
            let streams = try await service.getStreams(of: .vod, in: category.id)

            let count = try Category.countMedia(of: category.id, on: container.mainContext)
            if count == streams.count {
                logger.info("Category \(category.name) up to date with \(count) media.")
                continue
            } else {
                logger.info("Synchronizing category \(category.name)")
            }
            
            let context = ModelContext(container)

            let movieCategory = MovieCategory(from: category)
            context.insert(movieCategory)
            
            logger.info("Found \(streams.count) streams in category \(category.name)")
            
            for stream in streams {
                let vod = try await service.getVodInfo(of: stream.id)
                
                let source = MediaSource(
                    url: service.getPlayURL(
                        for: stream.id,
                        type: .vod,
                        containerExtension: stream.containerExtension ?? vod.data.containerExtension
                    ),
                    streamBitrate: vod.info.bitrate > 0 ? vod.info.bitrate : nil,
//                    audioDescription: streamAudioDescription(from: info.info.audio),
//                    videoResolution: streamVideoResolution(from: info.info.video),
//                    videoFrameRate: streamFrameRate(from: info.info.video)
                )
                
//                let movie = Movie(from: stream, movie: vod, category: movieCategory, source: source)
//                container.mainContext.insert(movie)
            }
            
            try context.save()
        }
    }
}
