//
//  Models.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 02.09.25.
//

import Foundation

@propertyWrapper
struct EmptyArray<T: Decodable>: Decodable {
    
    var wrappedValue: [T]

    // This is where the custom decoding logic lives
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try to decode the value as the expected type T.
        // If it fails, the 'try?' makes the result nil.
        self.wrappedValue = (try? container.decode([T].self)) ?? []
    }
}

@propertyWrapper
struct NonThrowingDecode<T: Decodable>: Decodable {
    
    var wrappedValue: T?

    // This is where the custom decoding logic lives
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try to decode the value as the expected type T.
        // If it fails, the 'try?' makes the result nil.
        self.wrappedValue = try? container.decode(T.self)
    }
}

@propertyWrapper
struct StringConvertibleDecode<T: LosslessStringConvertible & Decodable>: Decodable {
    
    var wrappedValue: T

    // This is where the custom decoding logic lives
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let value = try? container.decode(T.self) {
            self.wrappedValue = value
        } else {
            let string = try container.decode(String.self)
            guard let value = T(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Failed to convert string to \(T.self)")
            }
            self.wrappedValue = value
        }
    }
}

@propertyWrapper
struct OptionalStringConvertibleDecode<T: LosslessStringConvertible & Decodable>: Decodable {
    
    var wrappedValue: T?
    
    // This is where the custom decoding logic lives
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let value = try? container.decode(T.self) {
            self.wrappedValue = value
        } else if let string = try? container.decode(String.self),
                  let value = T(string) {
            self.wrappedValue = value
        } else {
            self.wrappedValue = nil
        }
    }
}

enum XtreamContentType: String {
    case live
    case vod
    case series
}

struct XtreamCategory: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case id = "category_id"
        case name = "category_name"
    }
}

struct XtreamStream: Decodable, Identifiable {
    let id: Int
    let name: String
    let categoryId: String
    let categoryIds: [Int]
    let containerExtension: String?
    @OptionalStringConvertibleDecode var rating: Double?
    @StringConvertibleDecode var rating5Based: Double
    let type: String
    @OptionalStringConvertibleDecode var tmdbId: Int? // sometimes string, sometimes int...
    let streamIcon: String
    let added: String
    let trailer: String
    let num: Int
    let isAdult: Int
    
    enum CodingKeys: String, CodingKey {
        case id = "stream_id"
        case name
        case categoryId = "category_id"
        case categoryIds = "category_ids"
        case containerExtension = "container_extension"
        case rating
        case rating5Based = "rating_5based"
        case type = "stream_type"
        case tmdbId = "tmdb"
        case streamIcon = "stream_icon"
        case added
        case trailer
        case num
        case isAdult = "is_adult"
    }
}

struct XtreamSeriesStream: Decodable, Identifiable {
    let id: Int
    let name: String
    let cover: String?
    let rating: Double?
    let plot: String?
    let categoryId: String?

    enum CodingKeys: String, CodingKey {
        case id = "series_id"
        case legacyId = "id"
        case name
        case title
        case cover
        case rating
        case plot
        case categoryId = "category_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let numericId = try? container.decode(Int.self, forKey: .id) {
            id = numericId
        } else if let stringId = try? container.decode(String.self, forKey: .id),
                  let numericId = Int(stringId) {
            id = numericId
        } else if let numericId = try? container.decode(Int.self, forKey: .legacyId) {
            id = numericId
        } else if let stringId = try? container.decode(String.self, forKey: .legacyId),
                  let numericId = Int(stringId) {
            id = numericId
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Unable to decode series_id")
        }

        if let decodedName = try container.decodeIfPresent(String.self, forKey: .name), !decodedName.isEmpty {
            name = decodedName
        } else {
            name = (try? container.decode(String.self, forKey: .title)) ?? "Untitled Series"
        }

        cover = try? container.decodeIfPresent(String.self, forKey: .cover)
        plot = try? container.decodeIfPresent(String.self, forKey: .plot)
        if let decodedCategory = try? container.decode(String.self, forKey: .categoryId) {
            categoryId = decodedCategory
        } else if let decodedCategory = try? container.decode(Int.self, forKey: .categoryId) {
            categoryId = String(decodedCategory)
        } else {
            categoryId = nil
        }

        if let numericRating = try? container.decode(Double.self, forKey: .rating) {
            rating = numericRating
        } else if let stringRating = try? container.decode(String.self, forKey: .rating),
                  let numericRating = Double(stringRating) {
            rating = numericRating
        } else {
            rating = nil
        }
    }
}

// - MARK: Vod
struct XtreamVod: Decodable, Identifiable {
    let info: XtreamVodInfo
    let data: XtreamVodData
    
    enum CodingKeys: String, CodingKey {
        case info
        case data = "movie_data"
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.info = try container.decode(XtreamVodInfo.self, forKey: .info)
        self.data = try container.decode(XtreamVodData.self, forKey: .data)
    }
    
    var id: Int { data.streamId }
}

struct XtreamVodInfo: Decodable {
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
    let episodeRunTime: Int?
    let genre: String
    let kinopoiskUrl: String?
    let movieImage: String
    let mpaaRating: String?
    let name: String
    let originalName: String
    let plot: String
    let ratingCountKinopoisk: Int?
    let releaseDate: String
    let status: String?
    let youtubeTrailer: String?

    // Properties that might fail to decode gracefully
    let audio: XtreamAudio?
    let durationSecs: Int?
    let rating: Double?
    let runtime: Int?
    let tmdbId: Int?
    let video: XtreamVideo?

    enum CodingKeys: String, CodingKey {
        case actors
        case age
        case audio
        case backdropPath = "backdrop_path"
        case bitrate
        case cast
        case country
        case coverBig = "cover_big"
        case description
        case director
        case duration
        case durationSecs = "duration_secs"
        case episodeRunTime = "episode_run_time"
        case genre
        case kinopoiskUrl = "kinopoisk_url"
        case movieImage = "movie_image"
        case mpaaRating = "mpaa_rating"
        case name
        case originalName = "o_name"
        case plot
        case rating
        case ratingCountKinopoisk = "rating_count_kinopoisk"
        case releaseDate = "releasedate"
        case runtime
        case status
        case tmdbId = "tmdb_id"
        case video
        case youtubeTrailer = "youtube_trailer"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode non-optional properties that should always exist
        self.actors = try container.decode(String.self, forKey: .actors)
        self.age = try container.decode(String.self, forKey: .age)
        self.bitrate = try container.decode(Int.self, forKey: .bitrate)
        self.cast = try container.decode(String.self, forKey: .cast)
        self.country = try container.decode(String.self, forKey: .country)
        self.coverBig = try container.decode(String.self, forKey: .coverBig)
        self.description = try container.decode(String.self, forKey: .description)
        self.director = try container.decode(String.self, forKey: .director)
        self.duration = try container.decode(String.self, forKey: .duration)
        self.genre = try container.decode(String.self, forKey: .genre)
        self.movieImage = try container.decode(String.self, forKey: .movieImage)
        self.name = try container.decode(String.self, forKey: .name)
        self.originalName = try container.decode(String.self, forKey: .originalName)
        self.plot = try container.decode(String.self, forKey: .plot)
        self.releaseDate = try container.decode(String.self, forKey: .releaseDate)

        // Decode optional properties using decodeIfPresent()
        self.episodeRunTime = try container.decodeIfPresent(Int.self, forKey: .episodeRunTime)
        self.kinopoiskUrl = try container.decodeIfPresent(String.self, forKey: .kinopoiskUrl)
        self.mpaaRating = try container.decodeIfPresent(String.self, forKey: .mpaaRating)
        self.ratingCountKinopoisk = try container.decodeIfPresent(Int.self, forKey: .ratingCountKinopoisk)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.youtubeTrailer = try emptyToNil(key: .youtubeTrailer)
        
        func emptyToNil<T: Collection & Decodable>(key: CodingKeys) throws -> T? {
            if let value = try container.decodeIfPresent(T.self, forKey: key) {
                return value.isEmpty ? nil : value
            }
            return nil
        }
        
        func lossless<T: LosslessStringConvertible & Decodable>(key: CodingKeys) -> T? {
            if let value = try? container.decode(T.self, forKey: key) {
                return value
            } else if let string = try? container.decode(String.self, forKey: key),
                      let value = T(string) {
                return value
            }
            return nil
        }
        
        // Decode properties that might fail using try?
        self.backdropPath = (try? container.decodeIfPresent([String].self, forKey: .backdropPath)) ?? [] // "null"
        self.audio = try? container.decode(XtreamAudio.self, forKey: .audio) // [] array when no data
        self.video = try? container.decode(XtreamVideo.self, forKey: .video) // [] array when no data
        self.durationSecs = lossless(key: .durationSecs) // String or number, but also "" sometimes
        self.rating = lossless(key: .rating) // String or number, but also "" sometimes
        self.runtime = lossless(key: .runtime) // String or number, but also "" sometimes
        self.tmdbId = lossless(key: .tmdbId) // String or number, but also "" sometimes
    }
}

struct XtreamVodData: Decodable {
    let added: String
    let categoryId: String
    let categoryIds: [Int]
    let containerExtension: String
    let customSid: String?
    let directSource: String
    let name: String
    let streamId: Int

    enum CodingKeys: String, CodingKey {
        case added
        case categoryId = "category_id"
        case categoryIds = "category_ids"
        case containerExtension = "container_extension"
        case customSid = "custom_sid"
        case directSource = "direct_source"
        case name
        case streamId = "stream_id"
    }
}

// - MARK: Series
struct XtreamSeries: Decodable {
    let seasons: [XtreamSeason]
    let info: XtreamShowInfo
    let episodes: [String: [XtreamEpisode]]
}

struct XtreamSeason: Decodable {
    let name: String
    let episodeCount: String
    let overview: String
    let airDate: String
    let cover: String
    let coverTmdb: String
    let seasonNumber: Int
    let coverBig: String
    let releaseDate: String
    let duration: String

    enum CodingKeys: String, CodingKey {
        case name
        case episodeCount = "episode_count"
        case overview
        case airDate = "air_date"
        case cover
        case coverTmdb = "cover_tmdb"
        case seasonNumber = "season_number"
        case coverBig = "cover_big"
        case releaseDate
        case duration
    }
}

struct XtreamShowInfo: Decodable {
    let name: String
    let cover: String
    let plot: String
    let cast: String
    let director: String
    let genre: String
    let releaseDate: String
    let releaseDateAlt: String
    let lastModified: String
    let rating: String
    let rating5based: String
    let backdropPath: [String]
    let tmdb: String
    let youtubeTrailer: String
    let episodeRunTime: String
    let categoryId: String
    let categoryIds: [Int]

    enum CodingKeys: String, CodingKey {
        case name, cover, plot, cast, director, genre
        case releaseDate
        case releaseDateAlt = "release_date"
        case lastModified = "last_modified"
        case rating
        case rating5based = "rating_5based"
        case backdropPath = "backdrop_path"
        case tmdb
        case youtubeTrailer = "youtube_trailer"
        case episodeRunTime = "episode_run_time"
        case categoryId = "category_id"
        case categoryIds = "category_ids"
    }
}

struct XtreamEpisode: Decodable {
    let id: String
    let episodeNum: Int
    let title: String
    let containerExtension: String
    let info: XtreamEpisodeInfo
    let customSid: String?
    let added: String
    let season: Int
    let directSource: String

    enum CodingKeys: String, CodingKey {
        case id
        case episodeNum = "episode_num"
        case title
        case containerExtension = "container_extension"
        case info
        case customSid = "custom_sid"
        case added
        case season
        case directSource = "direct_source"
    }
}

struct XtreamEpisodeInfo: Decodable {
    let airDate: String
    let crew: String
    let rating: Double
    let id: Int
    let movieImage: String
    let durationSecs: Int
    let duration: String
    let video: XtreamVideo
    let audio: XtreamAudio
    let bitrate: Int

    enum CodingKeys: String, CodingKey {
        case airDate = "air_date"
        case crew, rating, id
        case movieImage = "movie_image"
        case durationSecs = "duration_secs"
        case duration, video, audio, bitrate
    }
}

struct XtreamVideo: Decodable {
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
    let disposition: XtreamDisposition
    let tags: [String: String]

    enum CodingKeys: String, CodingKey {
        case index
        case codecName = "codec_name"
        case codecLongName = "codec_long_name"
        case profile
        case codecType = "codec_type"
        case codecTagString = "codec_tag_string"
        case codecTag = "codec_tag"
        case width, height
        case codedWidth = "coded_width"
        case codedHeight = "coded_height"
        case closedCaptions = "closed_captions"
        case filmGrain = "film_grain"
        case hasBFrames = "has_b_frames"
        case sampleAspectRatio = "sample_aspect_ratio"
        case displayAspectRatio = "display_aspect_ratio"
        case pixFmt = "pix_fmt"
        case level
        case colorRange = "color_range"
        case chromaLocation = "chroma_location"
        case fieldOrder = "field_order"
        case refs
        case rFrameRate = "r_frame_rate"
        case avgFrameRate = "avg_frame_rate"
        case timeBase = "time_base"
        case startPts = "start_pts"
        case startTime = "start_time"
        case extradataSize = "extradata_size"
        case disposition, tags
    }
}

struct XtreamAudio: Decodable {
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
    let disposition: XtreamDisposition
    let tags: [String: String]

    enum CodingKeys: String, CodingKey {
        case index
        case codecName = "codec_name"
        case codecLongName = "codec_long_name"
        case profile
        case codecType = "codec_type"
        case codecTagString = "codec_tag_string"
        case codecTag = "codec_tag"
        case sampleFmt = "sample_fmt"
        case sampleRate = "sample_rate"
        case channels
        case channelLayout = "channel_layout"
        case bitsPerSample = "bits_per_sample"
        case rFrameRate = "r_frame_rate"
        case avgFrameRate = "avg_frame_rate"
        case timeBase = "time_base"
        case startPts = "start_pts"
        case startTime = "start_time"
        case extradataSize = "extradata_size"
        case disposition, tags
    }
}

struct XtreamDisposition: Decodable {
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

    enum CodingKeys: String, CodingKey {
        case `default` = "default"
        case dub, original, comment, lyrics, karaoke, forced
        case hearingImpaired = "hearing_impaired"
        case visualImpaired = "visual_impaired"
        case cleanEffects = "clean_effects"
        case attachedPic = "attached_pic"
        case timedThumbnails = "timed_thumbnails"
        case captions, descriptions, metadata, dependent
        case stillImage = "still_image"
    }
}
