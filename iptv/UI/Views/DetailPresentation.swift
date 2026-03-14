//
//  DetailPresentation.swift
//  iptv
//
//  Created by Codex on 14.03.26.
//

import SwiftUI

enum DetailActionVariant {
    case primary
    case secondary
    case icon
    case chip(selected: Bool)

    fileprivate var size: DetailActionSize {
        switch self {
        case .primary, .secondary:
            .regular
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
        case .primary, .secondary:
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
        spacing: CGFloat = 22,
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
        .padding(.vertical, 26)

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
                HStack(alignment: .top, spacing: 12) {
                    ForEach(badges) { badge in
                        badgeView(for: badge)
                    }
                }
            }
        }
    }

    private func badgeView(for badge: DetailScoreBadgeModel) -> some View {
        let palette = palette(for: badge.sourceID)

        return VStack(alignment: .leading, spacing: 8) {
            Text(badge.label.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(palette.label)

            Text(badge.value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(minWidth: 112, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.fill)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(palette.stroke, lineWidth: 1)
                }
        }
    }

    private func palette(for sourceID: DetailScoreSourceID) -> (fill: Color, stroke: Color, label: Color) {
        switch sourceID {
        case .catalog:
            return (
                Color.white.opacity(0.07),
                Color.white.opacity(0.12),
                Color.white.opacity(0.72)
            )
        case .imdb:
            return (
                Color(red: 0.47, green: 0.36, blue: 0.02).opacity(0.48),
                Color(red: 0.98, green: 0.83, blue: 0.21).opacity(0.34),
                Color(red: 1.0, green: 0.9, blue: 0.42)
            )
        case .rottenTomatoes:
            return (
                Color(red: 0.42, green: 0.08, blue: 0.06).opacity(0.52),
                Color(red: 0.96, green: 0.31, blue: 0.22).opacity(0.34),
                Color(red: 1.0, green: 0.55, blue: 0.44)
            )
        case .tmdb:
            return (
                Color(red: 0.03, green: 0.25, blue: 0.27).opacity(0.56),
                Color(red: 0.18, green: 0.77, blue: 0.74).opacity(0.32),
                Color(red: 0.49, green: 0.92, blue: 0.89)
            )
        case .metacritic:
            return (
                Color(red: 0.16, green: 0.27, blue: 0.12).opacity(0.52),
                Color(red: 0.49, green: 0.83, blue: 0.28).opacity(0.34),
                Color(red: 0.73, green: 0.97, blue: 0.57)
            )
        }
    }
}

private enum DetailActionSize: Equatable {
    case regular
    case icon
    case chip

    var font: Font {
        switch self {
        case .regular:
            .headline.weight(.medium)
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
