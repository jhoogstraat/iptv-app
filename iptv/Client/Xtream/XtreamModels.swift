//
//  Models.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 02.09.25.
//

import Foundation
import SwiftUI

@propertyWrapper
struct IntOrString: Decodable {
    var wrappedValue: String
    
    enum CodingKeys: CodingKey {
        case wrappedValue
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.wrappedValue = try container.gracefullyDecode(.wrappedValue)
    }
}

private extension KeyedDecodingContainer {
    func gracefullyDecode(_ key: Key) throws -> String {
        guard contains(key) else {
            throw DecodingError.keyNotFound(key, .init(codingPath: [key], debugDescription: ""))
        }
        
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        
        throw DecodingError.typeMismatch(String.self, .init(codingPath: [key], debugDescription: "Failed to gracefully decode value."))
    }
}

struct Xtream {
    
    enum ContentType: String, Codable, Sendable {
        case live
        case vod
        case series
        
        var playbackPathComponent: String {
            switch self {
                case .live:
                    "live"
                case .vod:
                    "movie"
                case .series:
                    "series"
            }
        }
    }
    
    struct Category: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        
//        enum CodingKeys: String, CodingKey {
//            case id = "category_id"
//            case name = "category_name"
//        }
    }
    
    struct MovieStream: Decodable, Identifiable {
        let id: Int
        let number: Int
        let name: String
        let categoryId: String
        let containerExtension: String?
        let rating: Double?
        @IntOrString var tmdbId: String
        let streamIcon: String
        let added: String
        let trailer: String
        let num: Int
        let isAdult: Int
        
//        enum CodingKeys: String, CodingKey {
//            case id = "stream_id"
//            case number = "num"
//            case name
//            case categoryId = "category_id"
//            case containerExtension = "container_extension"
//            case rating
//            case tmdbId = "tmdb"
//            case streamIcon = "stream_icon"
//            case added
//            case trailer
//            case isAdult = "is_adult"
//        }
        
//        init(from decoder: Decoder) throws {
//            let container = try decoder.container(keyedBy: CodingKeys.self)
//            
//            id = try container.decode(Int.self, forKey: .id)
//            number = try container.decode(Int.self, forKey: .number)
//            name = try container.gracefullyDecode(.name)
//            categoryId = try container.gracefullyDecode(.categoryId)
//            containerExtension = try container.gracefullyDecode(.containerExtension)
//            rating = try container.decodeIfPresent(Double.self, forKey: .rating)
//            tmdbId = try? container.gracefullyDecode(.tmdbId)
//            streamIcon = try container.gracefullyDecode(.streamIcon)
//            added = try container.gracefullyDecode(.added)
//            trailer = try container.gracefullyDecode(.trailer)
//            num = try container.decode(Int.self, forKey: .number)
//            isAdult = try container.decode(Int.self, forKey: .isAdult)
//        }
    }
    
    struct SeriesStream: Decodable, Identifiable {
        let id: Int
        let categoryId: String?
        let name: String
        let cover: String?
        let rating: Double?
        let plot: String?
        
//        enum CodingKeys: String, CodingKey {
//            case name, cover, rating, plot
//            case id = "series_id"
//            case legacyId = "id"
//            case categoryId = "category_id"
//        }
//        
//        init(from decoder: Decoder) throws {
//            let container = try decoder.container(keyedBy: CodingKeys.self)
//            id = try container.decode(Int.self, forKey: .id)
//            categoryId = try container.gracefullyDecode(.categoryId)
//            name = try container.decode(String.self, forKey: .name)
//            cover = try container.decodeIfPresent(String.self, forKey: .cover)
//            plot = try container.decodeIfPresent(String.self, forKey: .plot)
//            rating = try container.decodeIfPresent(Double.self, forKey: .rating)
//        }
    }
    
    // - MARK: Vod
    struct Movie: Decodable {
        let info: MovieInfo
        let data: MovieData
        
//        enum CodingKeys: String, CodingKey {
//            case info
//            case data = "movie_data"
//        }
//        
//        init(from decoder: any Decoder) throws {
//            let container = try decoder.container(keyedBy: CodingKeys.self)
//            self.info = try container.decode(MovieInfo.self, forKey: .info)
//            self.data = try container.decode(MovieData.self, forKey: .data)
//        }
    }
    
    struct MovieInfo: Decodable {
        let actors: String
        let age: String
        let backdropPath: [String]
        let bitrate: Int
        let cast: String
        let country: String
        let coverBig: String
        let description: String
        let director: String
        let duration: String
        let episodeRuntime: Int?
        let genre: String
        let movieImage: String
        let mpaaRating: String?
        let name: String
        let originalName: String
        let plot: String
        let releaseDate: Date
        let status: String?
        let youtubeTrailer: String?
        
        let durationSecs: Int?
        let rating: Double?
        let runtime: Int?
        let tmdbId: String?
        let video: Video?
        let audio: Audio?
        
//        enum CodingKeys: String, CodingKey {
//            case actors
//            case age
//            case audio
//            case backdropPath = "backdrop_path"
//            case bitrate
//            case cast
//            case country
//            case coverBig = "cover_big"
//            case description
//            case director
//            case duration
//            case durationSecs = "duration_secs"
//            case episodeRuntime = "episode_run_time"
//            case genre
//            case movieImage = "movie_image"
//            case mpaaRating = "mpaa_rating"
//            case name
//            case originalName = "o_name"
//            case plot
//            case rating
//            case releaseDate = "releasedate"
//            case runtime
//            case status
//            case tmdbId = "tmdb_id"
//            case video
//            case youtubeTrailer = "youtube_trailer"
//        }
        
//        init(from decoder: Decoder) throws {
//            let container = try decoder.container(keyedBy: CodingKeys.self)
//            
//            actors = try container.gracefullyDecode(.actors)
//            age = try container.gracefullyDecode(.age)
//            bitrate = try container.decode(Int.self, forKey: .bitrate)
//            cast = try container.gracefullyDecode(.cast)
//            country = try container.gracefullyDecode(.country)
//            coverBig = try container.gracefullyDecode(.coverBig)
//            description = try container.gracefullyDecode(.description)
//            director = try container.gracefullyDecode(.director)
//            duration = try container.gracefullyDecode(.duration)
//            genre = try container.gracefullyDecode(.genre)
//            movieImage = try container.gracefullyDecode(.movieImage)
//            name = try container.gracefullyDecode(.name)
//            originalName = try container.gracefullyDecode(.originalName)
//            plot = try container.gracefullyDecode(.plot)
//            releaseDate = try container.decode(Date.self, forKey: .releaseDate)
//            episodeRuntime = try container.decodeIfPresent(Int.self, forKey: .episodeRuntime)
//            mpaaRating = try container.gracefullyDecode(.mpaaRating)
//            status = try container.gracefullyDecode(.status)
//            youtubeTrailer = try container.gracefullyDecode(.youtubeTrailer)
//            backdropPath = try container.decode([URL].self, forKey: .backdropPath)
//            audio = try container.decode(Audio.self, forKey: .audio)
//            video = try container.decode(Video.self, forKey: .video)
//            durationSecs = try container.decodeIfPresent(Int.self, forKey: .durationSecs)
//            rating = try container.decodeIfPresent(Double.self, forKey: .rating)
//            runtime = try container.decodeIfPresent(Int.self, forKey: .runtime)
//            tmdbId = try? container.gracefullyDecode(.tmdbId)
//        }
    }
    
    struct MovieData: Decodable {
        let added: String
        let categoryId: String
        let containerExtension: String
        let customSid: String?
        let directSource: String
        let name: String
        let streamId: Int
        
//        enum CodingKeys: String, CodingKey {
//            case added
//            case categoryId = "category_id"
//            case categoryIds = "category_ids"
//            case containerExtension = "container_extension"
//            case customSid = "custom_sid"
//            case directSource = "direct_source"
//            case name
//            case streamId = "stream_id"
//        }
        
//        init(from decoder: Decoder) throws {
//            let container = try decoder.container(keyedBy: CodingKeys.self)
//            added = try container.gracefullyDecode(.added)
//            categoryId = try container.gracefullyDecode(.categoryId)
//            containerExtension = try container.gracefullyDecode(.containerExtension)
//            customSid = try container.gracefullyDecode(.customSid)
//            directSource = try container.gracefullyDecode(.directSource)
//            name = try container.gracefullyDecode(.name)
//            streamId = try container.decode(Int.self, forKey: .streamId)
//        }
    }
    
    // - MARK: Series
    struct Series: Decodable {
        let seasons: [Season]
        let info: SeriesInfo
        let episodes: [String: [Episode]]
    }
    
    struct Season: Decodable {
        let name: String
        let seasonNumber: Int
        let episodeCount: Int
        let overview: String
        let airDate: String?
        let cover: String
        let coverBig: String
//        enum CodingKeys: String, CodingKey {
//            case name
//            case episodeCount = "episode_count"
//            case overview
//            case airDate = "air_date"
//            case cover
//            case seasonNumber = "season_number"
//            case coverBig = "cover_big"
//        }
    }
    
    struct SeriesInfo: Decodable {
        let name: String
        let cover: String
        let plot: String
        let cast: String
        let director: String
        let genre: String
        let releaseDate: Date
        let lastModified: String
        let rating: String
        let rating5based: String
        let backdropPath: [String]
        let tmdb: String
        let youtubeTrailer: String
        let episodeRuntime: String
        let categoryId: String
        
//        enum CodingKeys: String, CodingKey {
//            case name, cover, plot, cast, director, genre
//            case releaseDate = "release_date"
//            case lastModified = "last_modified"
//            case rating
//            case rating5based = "rating_5based"
//            case backdropPath = "backdrop_path"
//            case tmdb
//            case youtubeTrailer = "youtube_trailer"
//            case episodeRuntime = "episode_run_time"
//            case categoryId = "category_id"
//        }
//        
//        init(from decoder: Decoder) throws {
//            let container = try decoder.container(keyedBy: CodingKeys.self)
//            
//            name = try container.gracefullyDecode(.name)
//            cover = try container.gracefullyDecode(.cover)
//            plot = try container.gracefullyDecode(.plot)
//            cast = try container.gracefullyDecode(.cast)
//            director = try container.gracefullyDecode(.director)
//            genre = try container.gracefullyDecode(.genre)
//            releaseDate = try container.decode(Date.self, forKey: .releaseDate)
//            
//            lastModified = try container.gracefullyDecode(.lastModified)
//            rating = try container.gracefullyDecode(.rating)
//            rating5based = try container.gracefullyDecode(.rating5based)
//            backdropPath = try container.decode([URL].self, forKey: .backdropPath)
//            tmdb = try container.gracefullyDecode(.tmdb)
//            youtubeTrailer = try container.gracefullyDecode(.youtubeTrailer)
//            episodeRuntime = try container.gracefullyDecode(.episodeRuntime)
//            categoryId = try container.gracefullyDecode(.categoryId)
//        }
    }
    
    struct Episode: Decodable {
        let id: String
        let episodeNum: Int
        let title: String
        let containerExtension: String
        let info: EpisodeInfo
        let customSid: String?
        let added: String
        let season: Int
        let directSource: String
        
//        enum CodingKeys: String, CodingKey {
//            case id
//            case episodeNum = "episode_num"
//            case title
//            case containerExtension = "container_extension"
//            case info
//            case customSid = "custom_sid"
//            case added
//            case season
//            case directSource = "direct_source"
//        }
//        
//        init(from decoder: Decoder) throws {
//            let container = try decoder.container(keyedBy: CodingKeys.self)
//            
//            id = try container.gracefullyDecode(.id)
//            episodeNum = try container.decode(Int.self, forKey: .episodeNum)
//            title = try container.gracefullyDecode(.title)
//            containerExtension = try container.gracefullyDecode(.containerExtension)
//            info = try container.decode(EpisodeInfo.self, forKey: .info)
//            customSid = try container.gracefullyDecode(.customSid)
//            added = try container.gracefullyDecode(.added)
//            season = try container.decode(Int.self, forKey: .season)
//            directSource = try container.gracefullyDecode(.directSource)
//        }
    }
    
    struct EpisodeInfo: Decodable {
        let airDate: String
        let crew: String
        let rating: Double?
        let id: Int
        let movieImage: String
        let durationSecs: Int?
        let duration: String
        let video: Video?
        let audio: Audio?
        let bitrate: Int
        
//        enum CodingKeys: String, CodingKey {
//            case airDate = "air_date"
//            case crew, rating, id
//            case movieImage = "movie_image"
//            case durationSecs = "duration_secs"
//            case duration, video, audio, bitrate
//        }
//        
//        init(from decoder: Decoder) throws {
//            let container = try decoder.container(keyedBy: CodingKeys.self)
//            
//            airDate = try container.gracefullyDecode(.airDate)
//            crew = try container.gracefullyDecode(.crew)
//            rating = try container.decode(Double.self, forKey: .rating)
//            id = try container.decode(Int.self, forKey: .id)
//            movieImage = try container.gracefullyDecode(.movieImage)
//            durationSecs = try container.decode(Int.self, forKey: .durationSecs)
//            duration = try container.gracefullyDecode(.duration)
//            video = try? container.decode(Video.self, forKey: .video)
//            audio = try? container.decode(Audio.self, forKey: .audio)
//            bitrate = try container.decode(Int.self, forKey: .bitrate)
//        }
    }
    
    struct Video: Decodable {
        let index: Int
        let codecName: String
        let codecLongName: String
        let profile: String
        let codecType: String
        let codecTagString: String
        let codecTag: String
        let width, height, codedWidth, codedHeight: Int
        let closedCaptions: Int
        let filmGrain: Int
        let hasBFrames: Int
        let sampleAspectRatio: String
        let displayAspectRatio: String
        let pixFmt: String
        let level: Int
        let colorRange: String
        let chromaLocation: String
        let fieldOrder: String
        let refs: Int
        let rFrameRate: String
        let avgFrameRate: String
        let timeBase: String
        let startPts: Int
        let startTime: String
        let extradataSize: Int
        let disposition: Disposition
        let tags: [String: String]
        
//        enum CodingKeys: String, CodingKey {
//            case index
//            case codecName = "codec_name"
//            case codecLongName = "codec_long_name"
//            case profile
//            case codecType = "codec_type"
//            case codecTagString = "codec_tag_string"
//            case codecTag = "codec_tag"
//            case width, height
//            case codedWidth = "coded_width"
//            case codedHeight = "coded_height"
//            case closedCaptions = "closed_captions"
//            case filmGrain = "film_grain"
//            case hasBFrames = "has_b_frames"
//            case sampleAspectRatio = "sample_aspect_ratio"
//            case displayAspectRatio = "display_aspect_ratio"
//            case pixFmt = "pix_fmt"
//            case level
//            case colorRange = "color_range"
//            case chromaLocation = "chroma_location"
//            case fieldOrder = "field_order"
//            case refs
//            case rFrameRate = "r_frame_rate"
//            case avgFrameRate = "avg_frame_rate"
//            case timeBase = "time_base"
//            case startPts = "start_pts"
//            case startTime = "start_time"
//            case extradataSize = "extradata_size"
//            case disposition, tags
//        }
    }
    
    struct Audio: Decodable {
        let index: Int
        let codecName: String
        let codecLongName: String
        let profile: String
        let codecType: String
        let codecTagString: String
        let codecTag: String
        let sampleFmt: String
        let sampleRate: String
        let channels: Int
        let channelLayout: String
        let bitsPerSample: Int
        let rFrameRate: String
        let avgFrameRate: String
        let timeBase: String
        let startPts: Int
        let startTime: String
        let extradataSize: Int
        let disposition: Disposition
        let tags: [String: String]
        
//        enum CodingKeys: String, CodingKey {
//            case index
//            case codecName = "codec_name"
//            case codecLongName = "codec_long_name"
//            case profile
//            case codecType = "codec_type"
//            case codecTagString = "codec_tag_string"
//            case codecTag = "codec_tag"
//            case sampleFmt = "sample_fmt"
//            case sampleRate = "sample_rate"
//            case channels
//            case channelLayout = "channel_layout"
//            case bitsPerSample = "bits_per_sample"
//            case rFrameRate = "r_frame_rate"
//            case avgFrameRate = "avg_frame_rate"
//            case timeBase = "time_base"
//            case startPts = "start_pts"
//            case startTime = "start_time"
//            case extradataSize = "extradata_size"
//            case disposition, tags
//        }
    }
    
    struct Disposition: Decodable {
        let `default`: Int
        let dub: Int
        let original: Int
        let comment: Int
        let lyrics: Int
        let karaoke: Int
        let forced: Int
        let hearingImpaired: Int
        let visualImpaired: Int
        let cleanEffects: Int
        let attachedPic: Int
        let timedThumbnails: Int
        let captions: Int
        let descriptions: Int
        let metadata: Int
        let dependent: Int
        let stillImage: Int
        
//        enum CodingKeys: String, CodingKey {
//            case `default` = "default"
//            case dub, original, comment, lyrics, karaoke, forced
//            case hearingImpaired = "hearing_impaired"
//            case visualImpaired = "visual_impaired"
//            case cleanEffects = "clean_effects"
//            case attachedPic = "attached_pic"
//            case timedThumbnails = "timed_thumbnails"
//            case captions, descriptions, metadata, dependent
//            case stillImage = "still_image"
//        }
    }
}
