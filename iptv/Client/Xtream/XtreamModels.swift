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

private extension String {
    var xtreamTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var xtreamNilIfEmpty: String? {
        let value = xtreamTrimmed
        return value.isEmpty ? nil : value
    }
}

private extension Array where Element: Hashable {
    func xtreamUniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension KeyedDecodingContainer {
    func decodeNormalizedStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key),
           let normalized = value.xtreamNilIfEmpty {
            return normalized
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        return nil
    }

    func decodeNormalizedString(forKey key: Key, default defaultValue: String = "") -> String {
        decodeNormalizedStringIfPresent(forKey: key) ?? defaultValue
    }

    func decodeLosslessValueIfPresent<T>(_ type: T.Type, forKey key: Key) -> T?
    where T: LosslessStringConvertible & Decodable {
        if let value = try? decodeIfPresent(T.self, forKey: key) {
            return value
        }
        if let string = decodeNormalizedStringIfPresent(forKey: key) {
            return T(string)
        }
        return nil
    }

    func decodeLosslessValue<T>(_ type: T.Type, forKey key: Key, default defaultValue: T) -> T
    where T: LosslessStringConvertible & Decodable {
        decodeLosslessValueIfPresent(type, forKey: key) ?? defaultValue
    }

    func decodeNormalizedStringArray(forKey key: Key) -> [String] {
        if let values = try? decodeIfPresent([String].self, forKey: key) {
            return values.compactMap(\.xtreamNilIfEmpty).xtreamUniqued()
        }
        if let values = try? decodeIfPresent([Int].self, forKey: key) {
            return values.map(String.init).xtreamUniqued()
        }
        if let value = decodeNormalizedStringIfPresent(forKey: key) {
            let separators = CharacterSet(charactersIn: ",|;")
            let tokens = value
                .components(separatedBy: separators)
                .compactMap(\.xtreamNilIfEmpty)
            if tokens.count > 1 {
                return tokens.xtreamUniqued()
            }
            return [value]
        }
        return []
    }

    func decodeIdentifierStrings(forKey key: Key) -> [String] {
        if let values = try? decodeIfPresent([String].self, forKey: key) {
            return values.compactMap(\.xtreamNilIfEmpty).xtreamUniqued()
        }
        if let values = try? decodeIfPresent([Int].self, forKey: key) {
            return values.map(String.init).xtreamUniqued()
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return [String(value)]
        }
        if let rawValue = decodeNormalizedStringIfPresent(forKey: key) {
            let tokens = rawValue
                .split(whereSeparator: { !$0.isNumber })
                .map(String.init)
                .compactMap(\.xtreamNilIfEmpty)
            if !tokens.isEmpty {
                return tokens.xtreamUniqued()
            }
            return [rawValue]
        }
        return []
    }

    func decodeIdentifierInts(forKey key: Key) -> [Int] {
        decodeIdentifierStrings(forKey: key).compactMap(Int.init).xtreamUniqued()
    }
}

enum XtreamContentType: String, Codable, Sendable {
    case live
    case vod
    case series

    nonisolated var playbackPathComponent: String {
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

struct XtreamCategory: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case id = "category_id"
        case name = "category_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeNormalizedString(forKey: .id)
        name = container.decodeNormalizedString(forKey: .name, default: "Unknown Category")
    }
}

struct XtreamStream: Decodable, Identifiable {
    let id: Int
    let name: String
    let categoryId: String
    let categoryIds: [Int]
    let containerExtension: String?
    let rating: Double?
    let rating5Based: Double
    let type: String
    let tmdbId: Int?
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = container.decodeLosslessValue(Int.self, forKey: .id, default: 0)
        name = container.decodeNormalizedString(forKey: .name, default: "Untitled")
        categoryId = container.decodeNormalizedString(forKey: .categoryId)

        var normalizedCategoryIds = container.decodeIdentifierInts(forKey: .categoryIds)
        if let numericCategoryID = Int(categoryId), !normalizedCategoryIds.contains(numericCategoryID) {
            normalizedCategoryIds.insert(numericCategoryID, at: 0)
        }
        categoryIds = normalizedCategoryIds.xtreamUniqued()

        containerExtension = container.decodeNormalizedStringIfPresent(forKey: .containerExtension)
        rating = container.decodeLosslessValueIfPresent(Double.self, forKey: .rating)
        rating5Based = container.decodeLosslessValue(Double.self, forKey: .rating5Based, default: 0)
        type = container.decodeNormalizedString(forKey: .type, default: XtreamContentType.vod.rawValue).lowercased()
        tmdbId = container.decodeLosslessValueIfPresent(Int.self, forKey: .tmdbId)
        streamIcon = container.decodeNormalizedString(forKey: .streamIcon)
        added = container.decodeNormalizedString(forKey: .added)
        trailer = container.decodeNormalizedString(forKey: .trailer)
        num = container.decodeLosslessValue(Int.self, forKey: .num, default: 0)
        isAdult = container.decodeLosslessValue(Int.self, forKey: .isAdult, default: 0)
    }

    nonisolated func belongs(to categoryID: String) -> Bool {
        if categoryId == categoryID {
            return true
        }
        guard let numericCategoryID = Int(categoryID) else {
            return false
        }
        return categoryIds.contains(numericCategoryID)
    }
}

struct XtreamSeriesStream: Decodable, Identifiable {
    let id: Int
    let name: String
    let cover: String?
    let rating: Double?
    let plot: String?
    let categoryId: String?
    let categoryIds: [String]

    enum CodingKeys: String, CodingKey {
        case id = "series_id"
        case legacyId = "id"
        case name
        case title
        case cover
        case rating
        case plot
        case categoryId = "category_id"
        case categoryIds = "category_ids"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let numericId = container.decodeLosslessValueIfPresent(Int.self, forKey: .id) {
            id = numericId
        } else if let numericId = container.decodeLosslessValueIfPresent(Int.self, forKey: .legacyId) {
            id = numericId
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Unable to decode series_id")
        }

        if let decodedName = container.decodeNormalizedStringIfPresent(forKey: .name) {
            name = decodedName
        } else {
            name = container.decodeNormalizedString(forKey: .title, default: "Untitled Series")
        }

        cover = container.decodeNormalizedStringIfPresent(forKey: .cover)
        plot = container.decodeNormalizedStringIfPresent(forKey: .plot)
        categoryId = container.decodeNormalizedStringIfPresent(forKey: .categoryId)

        var decodedCategoryIds = container.decodeIdentifierStrings(forKey: .categoryIds)
        if let categoryId, !decodedCategoryIds.contains(categoryId) {
            decodedCategoryIds.insert(categoryId, at: 0)
        }
        categoryIds = decodedCategoryIds.xtreamUniqued()
        rating = container.decodeLosslessValueIfPresent(Double.self, forKey: .rating)
    }

    nonisolated func belongs(to categoryID: String) -> Bool {
        categoryIds.contains(categoryID)
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

        actors = container.decodeNormalizedString(forKey: .actors)
        age = container.decodeNormalizedString(forKey: .age)
        bitrate = container.decodeLosslessValue(Int.self, forKey: .bitrate, default: 0)
        cast = container.decodeNormalizedString(forKey: .cast)
        country = container.decodeNormalizedString(forKey: .country)
        coverBig = container.decodeNormalizedString(forKey: .coverBig)
        description = container.decodeNormalizedString(forKey: .description)
        director = container.decodeNormalizedString(forKey: .director)
        duration = container.decodeNormalizedString(forKey: .duration)
        genre = container.decodeNormalizedString(forKey: .genre)
        movieImage = container.decodeNormalizedString(forKey: .movieImage)
        name = container.decodeNormalizedString(forKey: .name)
        originalName = container.decodeNormalizedString(forKey: .originalName)
        plot = container.decodeNormalizedString(forKey: .plot)
        releaseDate = container.decodeNormalizedString(forKey: .releaseDate)

        episodeRunTime = container.decodeLosslessValueIfPresent(Int.self, forKey: .episodeRunTime)
        kinopoiskUrl = container.decodeNormalizedStringIfPresent(forKey: .kinopoiskUrl)
        mpaaRating = container.decodeNormalizedStringIfPresent(forKey: .mpaaRating)
        ratingCountKinopoisk = container.decodeLosslessValueIfPresent(Int.self, forKey: .ratingCountKinopoisk)
        status = container.decodeNormalizedStringIfPresent(forKey: .status)
        youtubeTrailer = container.decodeNormalizedStringIfPresent(forKey: .youtubeTrailer)

        backdropPath = container.decodeNormalizedStringArray(forKey: .backdropPath)
        audio = try? container.decode(XtreamAudio.self, forKey: .audio)
        video = try? container.decode(XtreamVideo.self, forKey: .video)
        durationSecs = container.decodeLosslessValueIfPresent(Int.self, forKey: .durationSecs)
        rating = container.decodeLosslessValueIfPresent(Double.self, forKey: .rating)
        runtime = container.decodeLosslessValueIfPresent(Int.self, forKey: .runtime)
        tmdbId = container.decodeLosslessValueIfPresent(Int.self, forKey: .tmdbId)
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        added = container.decodeNormalizedString(forKey: .added)
        categoryId = container.decodeNormalizedString(forKey: .categoryId)

        var normalizedCategoryIds = container.decodeIdentifierInts(forKey: .categoryIds)
        if let numericCategoryID = Int(categoryId), !normalizedCategoryIds.contains(numericCategoryID) {
            normalizedCategoryIds.insert(numericCategoryID, at: 0)
        }
        categoryIds = normalizedCategoryIds.xtreamUniqued()

        containerExtension = container.decodeNormalizedString(forKey: .containerExtension, default: "mp4")
        customSid = container.decodeNormalizedStringIfPresent(forKey: .customSid)
        directSource = container.decodeNormalizedString(forKey: .directSource)
        name = container.decodeNormalizedString(forKey: .name, default: "Untitled")
        streamId = container.decodeLosslessValue(Int.self, forKey: .streamId, default: 0)
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        name = container.decodeNormalizedString(forKey: .name)
        cover = container.decodeNormalizedString(forKey: .cover)
        plot = container.decodeNormalizedString(forKey: .plot)
        cast = container.decodeNormalizedString(forKey: .cast)
        director = container.decodeNormalizedString(forKey: .director)
        genre = container.decodeNormalizedString(forKey: .genre)

        let primaryReleaseDate = container.decodeNormalizedStringIfPresent(forKey: .releaseDate)
        let alternateReleaseDate = container.decodeNormalizedStringIfPresent(forKey: .releaseDateAlt)
        releaseDate = primaryReleaseDate ?? alternateReleaseDate ?? ""
        releaseDateAlt = alternateReleaseDate ?? primaryReleaseDate ?? ""

        lastModified = container.decodeNormalizedString(forKey: .lastModified)
        rating = container.decodeNormalizedString(forKey: .rating)
        rating5based = container.decodeNormalizedString(forKey: .rating5based)
        backdropPath = container.decodeNormalizedStringArray(forKey: .backdropPath)
        tmdb = container.decodeNormalizedString(forKey: .tmdb)
        youtubeTrailer = container.decodeNormalizedString(forKey: .youtubeTrailer)
        episodeRunTime = container.decodeNormalizedString(forKey: .episodeRunTime)
        categoryId = container.decodeNormalizedString(forKey: .categoryId)

        var normalizedCategoryIds = container.decodeIdentifierInts(forKey: .categoryIds)
        if let numericCategoryID = Int(categoryId), !normalizedCategoryIds.contains(numericCategoryID) {
            normalizedCategoryIds.insert(numericCategoryID, at: 0)
        }
        categoryIds = normalizedCategoryIds.xtreamUniqued()
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = container.decodeNormalizedString(forKey: .id)
        episodeNum = container.decodeLosslessValue(Int.self, forKey: .episodeNum, default: 0)
        title = container.decodeNormalizedString(forKey: .title, default: "Untitled Episode")
        containerExtension = container.decodeNormalizedString(forKey: .containerExtension, default: "mp4")
        info = try container.decode(XtreamEpisodeInfo.self, forKey: .info)
        customSid = container.decodeNormalizedStringIfPresent(forKey: .customSid)
        added = container.decodeNormalizedString(forKey: .added)
        season = container.decodeLosslessValue(Int.self, forKey: .season, default: 0)
        directSource = container.decodeNormalizedString(forKey: .directSource)
    }
}

struct XtreamEpisodeInfo: Decodable {
    let airDate: String
    let crew: String
    let rating: Double?
    let id: Int
    let movieImage: String
    let durationSecs: Int?
    let duration: String
    let video: XtreamVideo?
    let audio: XtreamAudio?
    let bitrate: Int

    enum CodingKeys: String, CodingKey {
        case airDate = "air_date"
        case crew, rating, id
        case movieImage = "movie_image"
        case durationSecs = "duration_secs"
        case duration, video, audio, bitrate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        airDate = container.decodeNormalizedString(forKey: .airDate)
        crew = container.decodeNormalizedString(forKey: .crew)
        rating = container.decodeLosslessValueIfPresent(Double.self, forKey: .rating)
        id = container.decodeLosslessValue(Int.self, forKey: .id, default: 0)
        movieImage = container.decodeNormalizedString(forKey: .movieImage)
        durationSecs = container.decodeLosslessValueIfPresent(Int.self, forKey: .durationSecs)
        duration = container.decodeNormalizedString(forKey: .duration)
        video = try? container.decode(XtreamVideo.self, forKey: .video)
        audio = try? container.decode(XtreamAudio.self, forKey: .audio)
        bitrate = container.decodeLosslessValue(Int.self, forKey: .bitrate, default: 0)
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
