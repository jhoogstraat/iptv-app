//
//  Mapper.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 06.09.25.
//

import Foundation

extension Category {
    convenience init(from xtream: XtreamCategory) {
        self.init(id: xtream.id, name: xtream.name)
    }
}

extension Video {    
    convenience init(from xtream: XtreamStream) {
        self.init(
            id: xtream.id,
            name: xtream.name,
            containerExtension: xtream.containerExtension ?? "mp4",
            contentType: xtream.type,
            coverImageURL: xtream.streamIcon,
            tmdbId: nil,
            rating: xtream.rating,
            addedAtRaw: xtream.added
        )
    }

    convenience init(from xtream: XtreamSeriesStream) {
        self.init(
            id: xtream.id,
            name: xtream.name,
            containerExtension: "mp4",
            contentType: XtreamContentType.series.rawValue,
            coverImageURL: xtream.cover,
            tmdbId: nil,
            rating: xtream.rating,
            addedAtRaw: nil
        )
    }

    convenience init(from cached: CachedVideoDTO) {
        self.init(
            id: cached.id,
            name: cached.name,
            containerExtension: cached.containerExtension,
            contentType: cached.contentType,
            coverImageURL: cached.coverImageURL,
            tmdbId: cached.tmdbId,
            rating: cached.rating,
            addedAtRaw: cached.added
        )
    }

    convenience init(from episode: XtreamEpisode) {
        self.init(
            id: Int(episode.id) ?? episode.info.id,
            name: episode.title,
            containerExtension: episode.containerExtension,
            contentType: XtreamContentType.series.rawValue,
            coverImageURL: episode.info.movieImage,
            tmdbId: nil,
            rating: episode.info.rating,
            addedAtRaw: episode.added
        )
    }
}

extension CachedVideoDTO {
    init(from xtream: XtreamStream) {
        self.init(
            id: xtream.id,
            name: xtream.name,
            containerExtension: xtream.containerExtension ?? "mp4",
            contentType: xtream.type,
            coverImageURL: xtream.streamIcon,
            tmdbId: nil,
            rating: xtream.rating,
            added: xtream.added
        )
    }

    init(from xtream: XtreamSeriesStream) {
        self.init(
            id: xtream.id,
            name: xtream.name,
            containerExtension: "mp4",
            contentType: XtreamContentType.series.rawValue,
            coverImageURL: xtream.cover,
            tmdbId: nil,
            rating: xtream.rating,
            added: nil
        )
    }
}

extension VideoInfo {
    convenience init(from xtream: XtreamVod) {
        self.init(
            images: xtream.info.backdropPath.compactMap(URL.init),
            plot: xtream.info.plot.isEmpty ? xtream.info.description : xtream.info.plot,
            cast: xtream.info.cast,
            director: xtream.info.director,
            genre: xtream.info.genre,
            releaseDate: xtream.info.releaseDate,
            durationLabel: xtream.info.duration,
            runtimeMinutes: xtream.info.runtime ?? xtream.info.durationSecs.map { $0 / 60 },
            ageRating: xtream.info.age,
            country: xtream.info.country,
            rating: xtream.info.rating,
            streamBitrate: xtream.info.bitrate > 0 ? xtream.info.bitrate : nil,
            audioDescription: streamAudioDescription(from: xtream.info.audio),
            videoResolution: streamVideoResolution(from: xtream.info.video),
            videoFrameRate: streamFrameRate(from: xtream.info.video)
        )
    }
}

private func streamAudioDescription(from audio: XtreamAudio?) -> String {
    guard let audio else { return "" }

    let layout = audio.channelLayout.trimmingCharacters(in: .whitespacesAndNewlines)
    if !layout.isEmpty {
        switch layout.lowercased() {
        case "stereo":
            return "Stereo"
        case "mono":
            return "Mono"
        default:
            return layout.replacingOccurrences(of: "(side)", with: "").capitalized
        }
    }

    let codec = audio.codecLongName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !codec.isEmpty {
        return codec.capitalized
    }

    return audio.codecName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
}

private func streamVideoResolution(from video: XtreamVideo?) -> String {
    guard let video,
          video.width > 0,
          video.height > 0
    else { return "" }

    return "\(video.width)x\(video.height)"
}

private func streamFrameRate(from video: XtreamVideo?) -> Double? {
    streamFrameRate(from: video?.avgFrameRate) ?? streamFrameRate(from: video?.rFrameRate)
}

private func streamFrameRate(from rawValue: String?) -> Double? {
    guard let rawValue else { return nil }

    let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return nil }

    if normalized.contains("/") {
        let components = normalized.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2,
              let numerator = Double(components[0]),
              let denominator = Double(components[1]),
              denominator != 0
        else { return nil }
        return numerator / denominator
    }

    return Double(normalized)
}
