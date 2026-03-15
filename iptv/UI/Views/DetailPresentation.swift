//
//  DetailPresentation.swift
//  iptv
//
//  Created by Codex on 14.03.26.
//

import SwiftUI

enum DetailSpacing {
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
}

enum DetailActionVariant {
    case primary
    case secondary
    case compactPrimary
    case compactSecondary
    case icon
    case chip(selected: Bool)

    fileprivate var size: DetailActionSize {
        switch self {
        case .primary, .secondary:
            .regular
        case .compactPrimary, .compactSecondary:
            .compact
        case .icon:
            .icon
        case .chip:
            .chip
        }
    }

    fileprivate var palette: DetailActionPalette {
        switch self {
        case .primary:
            return DetailActionPalette(
                fill: Color.white.opacity(0.14),
                stroke: Color.white.opacity(0.18),
                foreground: .white,
                shadow: Color.black.opacity(0.24),
                shape: .capsule
            )
        case .secondary:
            return DetailActionPalette(
                fill: Color.white.opacity(0.08),
                stroke: Color.white.opacity(0.12),
                foreground: .white.opacity(0.96),
                shadow: Color.black.opacity(0.16),
                shape: .capsule
            )
        case .compactPrimary:
            return DetailActionPalette(
                fill: Color.white.opacity(0.14),
                stroke: Color.white.opacity(0.18),
                foreground: .white,
                shadow: Color.black.opacity(0.18),
                shape: .capsule
            )
        case .compactSecondary:
            return DetailActionPalette(
                fill: Color.white.opacity(0.08),
                stroke: Color.white.opacity(0.12),
                foreground: .white.opacity(0.96),
                shadow: Color.black.opacity(0.14),
                shape: .capsule
            )
        case .icon:
            return DetailActionPalette(
                fill: Color.white.opacity(0.08),
                stroke: Color.white.opacity(0.12),
                foreground: .white.opacity(0.96),
                shadow: Color.black.opacity(0.14),
                shape: .circle
            )
        case .chip(let selected):
            return DetailActionPalette(
                fill: selected ? Color.white.opacity(0.14) : Color.white.opacity(0.07),
                stroke: selected ? Color.white.opacity(0.18) : Color.white.opacity(0.10),
                foreground: .white,
                shadow: Color.black.opacity(0.12),
                shape: .capsule
            )
        }
    }

    var fillsWidth: Bool {
        switch self {
        case .primary, .secondary, .compactPrimary, .compactSecondary:
            true
        case .icon, .chip:
            false
        }
    }
}

enum DownloadStatusBadgePresentation {
    case capsule
    case detailAction(DetailActionVariant)
}

struct DetailActionStyle: ButtonStyle {
    let variant: DetailActionVariant

    func makeBody(configuration: Configuration) -> some View {
        DetailActionStyleBody(
            label: configuration.label,
            variant: variant,
            isPressed: configuration.isPressed
        )
    }
}

struct DetailContentLayout<Content: View>: View {
    let isCompact: Bool
    let spacing: CGFloat
    let availableWidth: CGFloat?
    private let content: () -> Content

    init(
        isCompact: Bool,
        spacing: CGFloat = DetailSpacing.lg,
        availableWidth: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isCompact = isCompact
        self.spacing = spacing
        self.availableWidth = availableWidth
        self.content = content
    }

    var body: some View {
        let horizontalPadding: CGFloat = isCompact ? 20 : 28
        let column = VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, DetailSpacing.sm)
        .padding(.bottom, DetailSpacing.xl)

        Group {
            if isCompact {
                if let availableWidth {
                    column
                        .frame(width: max(availableWidth, 0), alignment: .leading)
                } else {
                    column
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                column
                    .frame(maxWidth: 920, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

struct DetailAlternativeSource: Identifiable {
    let video: Video
    let categoryNames: [String]
    let languageCodes: [String]

    var id: String {
        "\(video.contentType):\(video.id)"
    }

    var subtitle: String {
        let languages = languageCodes.isEmpty ? nil : languageCodes.joined(separator: " / ")
        let categories = categoryNames.isEmpty ? nil : categoryNames.joined(separator: " • ")

        return [languages, categories]
            .compactMap { $0 }
            .joined(separator: "  •  ")
    }
}

struct DetailAlternativeSourcesSheet<Destination: View>: View {
    let title: String
    let isLoading: Bool
    let errorMessage: String?
    let sources: [DetailAlternativeSource]
    let onRetry: () -> Void
    let destination: (Video) -> Destination

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Searching other categories for matching sources...")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                } else if let errorMessage {
                    VStack(spacing: 14) {
                        Text(errorMessage)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Try Again", action: onRetry)
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                } else if sources.isEmpty {
                    VStack(spacing: 12) {
                        Text("No other sources found.")
                            .font(.headline)
                        Text("Try again after more categories have been synced.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                } else {
                    List(sources) { source in
                        NavigationLink {
                            destination(source.video)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(source.video.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                if !source.subtitle.isEmpty {
                                    Text(source.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DetailHeroBackdrop: View {
    let artworkURL: URL?
    let height: CGFloat
    let topInset: CGFloat
    let collapseProgress: CGFloat
    let scrollOffset: CGFloat
    let artworkContentMode: ContentMode

    init(
        artworkURL: URL?,
        height: CGFloat,
        topInset: CGFloat,
        collapseProgress: CGFloat,
        scrollOffset: CGFloat,
        artworkContentMode: ContentMode = .fill
    ) {
        self.artworkURL = artworkURL
        self.height = height
        self.topInset = topInset
        self.collapseProgress = collapseProgress
        self.scrollOffset = scrollOffset
        self.artworkContentMode = artworkContentMode
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black

            artworkLayer
                .scaleEffect(stretchScale, anchor: .top)
                .offset(y: parallaxOffset)
                .opacity(imageOpacity)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0.0),
                            .init(color: .white, location: 0.3),
                            .init(color: .white.opacity(0.86), location: 0.52),
                            .init(color: .white.opacity(0.28), location: 0.74),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.42),
                    Color.black.opacity(0.82),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Color.black.opacity(Double(collapseProgress) * 0.3)
        }
        .frame(height: height + topInset)
        .frame(maxWidth: .infinity)
        .clipped()
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private var artworkLayer: some View {
        if let artworkURL {
            AsyncImage(url: artworkURL) { phase in
                switch phase {
                case .success(let image):
                    if artworkContentMode == .fit {
                        image.boundedCoverArtwork()
                    } else {
                        image.boundedFillArtwork()
                    }
                default:
                    Color.white.opacity(0.05)
                }
            }
        } else {
            Color.white.opacity(0.05)
        }
    }

    private var imageOpacity: Double {
        max(0.0, 1.0 - (Double(collapseProgress) * 0.78))
    }

    private var parallaxOffset: CGFloat {
        if scrollOffset < 0 {
            return scrollOffset * 0.18
        }

        return scrollOffset * 0.08
    }

    private var stretchScale: CGFloat {
        let pullDownDistance = max(scrollOffset, 0)
        return 1.0 + min(pullDownDistance / max(height, 1), 0.12)
    }
}

@MainActor
func loadDetailAlternativeSources(
    for referenceVideo: Video,
    preferredTitle: String,
    catalog: Catalog
) async throws -> [DetailAlternativeSource] {
    let contentType = referenceVideo.xtreamContentType
    guard contentType == .vod || contentType == .series else { return [] }

    try await catalog.ensureBootstrapLoaded()

    let referenceTitleKey = detailAlternativeSourceTitleKey(preferredTitle)
    let referenceTMDBID = detailAlternativeSourceID(referenceVideo.tmdbId)
    let referenceLanguage = referenceVideo.language?.uppercased()

    struct Accumulator {
        var video: Video
        var categoryNames: Set<String>
        var languageCodes: Set<String>
    }

    var groupedSources: [String: Accumulator] = [:]

    for category in catalog.categories(for: contentType) {
        guard let cachedVideos = catalog.cachedVideos(in: category, contentType: contentType) else { continue }

        for candidate in cachedVideos {
            guard candidate.id != referenceVideo.id else { continue }
            guard detailAlternativeSourceMatches(
                candidate,
                referenceTitleKey: referenceTitleKey,
                referenceTMDBID: referenceTMDBID
            ) else { continue }

            let key = "\(candidate.contentType):\(candidate.id)"
            var accumulator = groupedSources[key] ?? Accumulator(
                video: candidate,
                categoryNames: [],
                languageCodes: []
            )

            accumulator.categoryNames.insert(category.groupedDisplayName)
            if let languageCode = (candidate.language ?? category.languageGroupCode)?.uppercased() {
                accumulator.languageCodes.insert(languageCode)
            }
            groupedSources[key] = accumulator
        }
    }

    return groupedSources.values
        .map { source in
            DetailAlternativeSource(
                video: source.video,
                categoryNames: source.categoryNames.sorted(),
                languageCodes: source.languageCodes.sorted()
            )
        }
        .sorted { lhs, rhs in
            let lhsSharesLanguage = referenceLanguage != nil && lhs.languageCodes.contains(referenceLanguage!)
            let rhsSharesLanguage = referenceLanguage != nil && rhs.languageCodes.contains(referenceLanguage!)
            if lhsSharesLanguage != rhsSharesLanguage {
                return !lhsSharesLanguage && rhsSharesLanguage
            }
            if lhs.categoryNames.count != rhs.categoryNames.count {
                return lhs.categoryNames.count > rhs.categoryNames.count
            }
            return lhs.video.name.localizedCaseInsensitiveCompare(rhs.video.name) == .orderedAscending
        }
}

private func detailAlternativeSourceMatches(
    _ candidate: Video,
    referenceTitleKey: String,
    referenceTMDBID: String?
) -> Bool {
    if let referenceTMDBID,
       let candidateTMDBID = detailAlternativeSourceID(candidate.tmdbId),
       referenceTMDBID == candidateTMDBID {
        return true
    }

    let candidateTitleKey = detailAlternativeSourceTitleKey(candidate.name)
    guard !referenceTitleKey.isEmpty, !candidateTitleKey.isEmpty else { return false }

    if referenceTitleKey == candidateTitleKey {
        return true
    }

    let minimumLength = min(referenceTitleKey.count, candidateTitleKey.count)
    guard minimumLength >= 8 else { return false }

    return referenceTitleKey.contains(candidateTitleKey) || candidateTitleKey.contains(referenceTitleKey)
}

private func detailAlternativeSourceTitleKey(_ value: String?) -> String {
    let baseValue = value.map { LanguageTaggedText($0).groupedDisplayName } ?? ""
    let folded = baseValue.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

    let strippedQuality = folded.replacingOccurrences(
        of: #"\b(2160p|1080p|720p|480p|4k|uhd|fhd|hd|sd|hdr|hdr10|dv|dovi|bluray|blu-ray|brrip|bdrip|webrip|web-rip|webdl|web-dl|remux|x264|x265|h264|h265|hevc|aac|ddp|dd\+|atmos)\b"#,
        with: " ",
        options: [.regularExpression, .caseInsensitive]
    )

    let alphanumeric = strippedQuality.replacingOccurrences(
        of: #"[^a-zA-Z0-9]+"#,
        with: " ",
        options: .regularExpression
    )

    return alphanumeric
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

private func detailAlternativeSourceID(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

struct DetailMetaPill: View {
    let text: String
    let systemImage: String?

    init(_ text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
            }

            Text(text)
                .font(.title3.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.12))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                }
        }
    }
}

struct DetailCollapsedHeaderBar: View {
    let title: String
    let artworkURL: URL?
    let titleArtworkURL: URL?
    let progress: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            if let titleArtworkURL {
                AsyncImage(url: titleArtworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: 132, maxHeight: 30, alignment: .leading)
            } else {
                if let artworkURL {
                    AsyncImage(url: artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            Color.white.opacity(0.06)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .clipShape(.rect(cornerRadius: 9))
                }

                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.42))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
        }
        .shadow(color: Color.black.opacity(0.22), radius: 16, y: 10)
        .opacity(progress)
        .scaleEffect(0.96 + (progress * 0.04))
        .animation(.easeOut(duration: 0.2), value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

struct DetailSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.3)
            .foregroundStyle(.secondary)
    }
}

enum DetailHeroProgressPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum DetailScoreSourceID: String {
    case catalog
    case imdb
    case rottenTomatoes
    case tmdb
    case metacritic
}

struct DetailScoreBadgeModel: Equatable, Identifiable {
    let sourceID: DetailScoreSourceID
    let label: String
    let value: String

    var id: String {
        sourceID.rawValue
    }
}

struct DetailScoreSource {
    let id: DetailScoreSourceID
    let label: String
    private let valueStyle: DetailScoreValueStyle

    func badgeModel(value: Double?) -> DetailScoreBadgeModel? {
        guard let value else { return nil }
        return DetailScoreBadgeModel(sourceID: id, label: label, value: formattedValue(number: value))
    }

    func badgeModel(text: String?) -> DetailScoreBadgeModel? {
        guard let normalized = normalizedText(text) else { return nil }

        switch valueStyle {
        case .decimal:
            let candidate = normalized.replacingOccurrences(of: ",", with: ".")
            if let numericValue = Double(candidate) {
                return DetailScoreBadgeModel(sourceID: id, label: label, value: formattedValue(number: numericValue))
            }
        case .text:
            break
        }

        return DetailScoreBadgeModel(sourceID: id, label: label, value: normalized)
    }

    private func formattedValue(number: Double) -> String {
        switch valueStyle {
        case .decimal(let fractionLength):
            return number.formatted(
                .number
                    .precision(.fractionLength(fractionLength))
                    .locale(Locale(identifier: "en_US_POSIX"))
            )
        case .text:
            return String(number)
        }
    }

    private func normalizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static let catalog = DetailScoreSource(id: .catalog, label: "Rating", valueStyle: .decimal(fractionLength: 1))
    static let imdb = DetailScoreSource(id: .imdb, label: "IMDb", valueStyle: .decimal(fractionLength: 1))
    static let rottenTomatoes = DetailScoreSource(id: .rottenTomatoes, label: "Rotten", valueStyle: .text)
    static let tmdb = DetailScoreSource(id: .tmdb, label: "TMDB", valueStyle: .decimal(fractionLength: 1))
    static let metacritic = DetailScoreSource(id: .metacritic, label: "Metacritic", valueStyle: .text)
}

struct DetailScoreBadgeRow: View {
    let badges: [DetailScoreBadgeModel]

    var body: some View {
        if !badges.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(badges) { badge in
                        badgeView(for: badge)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func badgeView(for badge: DetailScoreBadgeModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(badge.value)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                Image(systemName: symbolName(for: badge.sourceID))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(iconColor(for: badge.sourceID))

                Text(badge.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.56))
            }
        }
        .frame(minWidth: 74, alignment: .leading)
    }

    private func symbolName(for sourceID: DetailScoreSourceID) -> String {
        switch sourceID {
        case .catalog:
            return "square.grid.2x2.fill"
        case .imdb:
            return "film.fill"
        case .rottenTomatoes:
            return "record.circle.fill"
        case .tmdb:
            return "sparkles.tv.fill"
        case .metacritic:
            return "chart.bar.fill"
        }
    }

    private func iconColor(for sourceID: DetailScoreSourceID) -> Color {
        switch sourceID {
        case .catalog:
            return Color.white.opacity(0.64)
        case .imdb:
            return Color(red: 1.0, green: 0.9, blue: 0.42)
        case .rottenTomatoes:
            return Color(red: 1.0, green: 0.55, blue: 0.44)
        case .tmdb:
            return Color(red: 0.49, green: 0.92, blue: 0.89)
        case .metacritic:
            return Color(red: 0.73, green: 0.97, blue: 0.57)
        }
    }
}

private enum DetailActionSize: Equatable {
    case regular
    case compact
    case icon
    case chip

    var font: Font {
        switch self {
        case .regular:
            .headline.weight(.medium)
        case .compact:
            .subheadline.weight(.semibold)
        case .icon:
            .headline.weight(.medium)
        case .chip:
            .subheadline.weight(.medium)
        }
    }

    var minHeight: CGFloat {
        switch self {
        case .regular:
            50
        case .compact:
            38
        case .icon:
            44
        case .chip:
            36
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .regular:
            16
        case .compact:
            12
        case .icon:
            0
        case .chip:
            13
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .regular:
            0
        case .compact:
            0
        case .icon:
            0
        case .chip:
            0
        }
    }
}

private enum DetailActionShape {
    case capsule
    case circle
}

private struct DetailActionPalette {
    let fill: Color
    let stroke: Color
    let foreground: Color
    let shadow: Color
    let shape: DetailActionShape
}

private struct DetailActionStyleBody<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled

    let label: Label
    let variant: DetailActionVariant
    let isPressed: Bool

    var body: some View {
        let size = variant.size
        let palette = variant.palette

        label
            .font(size.font)
            .foregroundStyle(palette.foreground)
            .frame(
                minWidth: size == .icon ? size.minHeight : nil,
                minHeight: size.minHeight
            )
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background {
                backgroundShape(palette: palette)
            }
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: isPressed)
    }

    @ViewBuilder
    private func backgroundShape(palette: DetailActionPalette) -> some View {
        switch palette.shape {
        case .capsule:
            Capsule(style: .continuous)
                .fill(palette.fill)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(palette.stroke, lineWidth: isPressed ? 1.2 : 1)
                }
                .shadow(color: palette.shadow, radius: 14, y: 8)
        case .circle:
            Circle()
                .fill(palette.fill)
                .overlay {
                    Circle()
                        .stroke(palette.stroke, lineWidth: isPressed ? 1.2 : 1)
                }
                .shadow(color: palette.shadow, radius: 14, y: 8)
        }
    }
}

private enum DetailScoreValueStyle {
    case decimal(fractionLength: Int)
    case text
}

#Preview("Detail Styling") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(alignment: .leading, spacing: 18) {
            DetailCollapsedHeaderBar(title: "2001: A Space Odyssey", artworkURL: nil, titleArtworkURL: nil, progress: 1)

            HStack(spacing: 12) {
                Button {
                } label: {
                    Label("Continue Watching", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DetailActionStyle(variant: .primary))
            }

            HStack(spacing: 12) {
                Button {
                } label: {
                    Image(systemName: "heart")
                }
                .buttonStyle(DetailActionStyle(variant: .icon))

                Button {
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(DetailActionStyle(variant: .icon))

                Button {
                } label: {
                    Label("Season 1", systemImage: "sparkles")
                }
                .buttonStyle(DetailActionStyle(variant: .chip(selected: true)))
            }

            HStack(spacing: 12) {
                DetailMetaPill("8", systemImage: "star.fill")
                Text("1968")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
                Text("149 min")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
        .padding(24)
    }
    .frame(width: 390, height: 320)
}
