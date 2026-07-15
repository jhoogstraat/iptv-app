import SwiftUI

struct MediaDetailDestination: View {
    let media: Media
    let categoryTitle: String?

    init(media: Media, categoryTitle: String? = nil) {
        self.media = media
        self.categoryTitle = categoryTitle
    }

    var body: some View {
        switch media.type {
        case .movie:
            MovieDetailScreen(movie: media, categoryTitle: categoryTitle)
        case .series:
            SeriesDetailScreen(series: media, categoryTitle: categoryTitle)
        case .episode:
            EpisodeDetailTile(series: nil, episode: media)
        case .live:
            ScopedPlaceholderView(
                title: "Live TV details unavailable",
                message: "Live channel details are not part of this local-data foundation workstream."
            )
        }
    }
}
