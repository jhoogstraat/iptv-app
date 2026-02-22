//
//  VideoInfo.swift
//  iptv
//
//  Created by HOOGSTRAAT, JOSHUA on 09.09.25.
//

import Foundation
import SwiftData

@Model
class VideoInfo: Identifiable {
    @Relationship var video: Video?
    var images: [URL]
    var plot: String
    var cast: String
    var director: String
    var genre: String
    var releaseDate: String
    var durationLabel: String
    var runtimeMinutes: Int?
    var ageRating: String
    var country: String
    var rating: Double?

    init(
        images: [URL],
        plot: String,
        cast: String,
        director: String,
        genre: String,
        releaseDate: String,
        durationLabel: String,
        runtimeMinutes: Int?,
        ageRating: String,
        country: String,
        rating: Double?
    ) {
        self.video = nil
        self.images = images
        self.plot = plot
        self.cast = cast
        self.director = director
        self.genre = genre
        self.releaseDate = releaseDate
        self.durationLabel = durationLabel
        self.runtimeMinutes = runtimeMinutes
        self.ageRating = ageRating
        self.country = country
        self.rating = rating
    }
}
